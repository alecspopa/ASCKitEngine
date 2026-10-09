import ASCKitAPI
import Foundation

/// The app's library and this project's record of what is in it.
public struct LibraryState: Sendable {
    public let libraryID: String
    public let record: AssetRecord

    public init(libraryID: String, record: AssetRecord) {
        self.libraryID = libraryID
        self.record = record
    }
}

/// Why a read of the images could not go on.
public enum LibraryReadError: Error, Equatable, CustomLocalizedStringResourceConvertible {
    /// App Store Connect has no asset library for this app.
    case noLibrary
    /// A push of images from a read that left the images out.
    case notRead

    public var localizedStringResource: LocalizedStringResource {
        switch self {
        case .noLibrary:
            LocalizedStringResource("""
            App Store Connect has no asset library for this app, so ASCKit cannot read or write \
            its screenshots. Open the app in App Store Connect once, then read again.
            """, bundle: .here)
        case .notRead:
            LocalizedStringResource("Read App Store Connect with the images, then push them.", bundle: .here)
        }
    }
}

extension LibraryReadError: CustomStringConvertible {
    public var description: String { String(localized: localizedStringResource) }
}

extension PushSession {
    /// Reads the library and brings the record up to date with it.
    ///
    /// The record learns the screenshots App Store Connect moved from the old
    /// sets, and forgets the assets that are gone. It is written back only
    /// when that changed it. The reference data goes into the cache on the
    /// way, for a check without a network connection.
    func readLibrary(appID: String, listing: RemoteListing?) async throws -> LibraryState? {
        guard let library = try await client.readAssetLibrary(appID: appID) else { return nil }

        let stored = try AssetRecordStore.load(in: project)
        var record = stored
        if let listing {
            record.adopt(sets: listing.screenshotSets, placements: listing.placements)
        }
        record.keepOnly(library)
        if record != stored {
            try AssetRecordStore.save(record, in: project)
        }

        if let refData = try? await client.assetLibraryRefData() {
            try? RefDataCache.save(refData, in: project)
        }
        return LibraryState(libraryID: library.id, record: record)
    }

    /// The changing screenshot slots of a version, with the page each one
    /// goes on.
    static func targets(in plan: ChangePlan, listing: RemoteListing) -> [LibraryPusher.Target] {
        let previews = plan.previewPlans.filter(\.changesAnything).map { item in
            LibraryPusher.Target(
                id: item.id,
                label: item.locale,
                deviceClassID: item.deviceClass.id,
                parent: .versionLocalization(id: listing.versionLocalizations[item.locale]?.id ?? ""),
                files: item.localFiles.map(\.libraryFile),
                slot: item.library
            )
        }
        let creative = plan.creativePlans.filter(\.changesAnything).map { item in
            LibraryPusher.Target(
                id: item.id,
                label: item.locale,
                deviceClassID: item.role.rawValue,
                parent: .versionLocalization(id: listing.versionLocalizations[item.locale]?.id ?? ""),
                files: item.file.map { [$0.libraryFile] } ?? [],
                slot: item.library
            )
        }
        return screenshotTargets(in: plan, listing: listing) + previews + creative
    }

    private static func screenshotTargets(in plan: ChangePlan, listing: RemoteListing) -> [LibraryPusher.Target] {
        plan.screenshotPlans.compactMap { item in
            guard item.changesAnything else { return nil }
            let slot = item.library
            // A language with no page here fails in the pusher, with its own
            // reason, rather than going missing from the result.
            let localizationID = listing.versionLocalizations[item.locale]?.id ?? ""
            return LibraryPusher.Target(
                id: item.id,
                label: item.locale,
                deviceClassID: item.deviceClass.id,
                parent: .versionLocalization(id: localizationID),
                files: item.localFiles.map(\.libraryFile),
                slot: slot
            )
        }
    }

    static func targets(in plan: ExperimentPlan) -> [LibraryPusher.Target] {
        let previews = plan.changingPreviewSets.map { item in
            LibraryPusher.Target(
                id: item.id,
                label: item.label,
                deviceClassID: item.deviceClass.id,
                parent: .treatmentLocalization(id: item.treatmentLocalizationID),
                files: item.localFiles.map(\.libraryFile),
                slot: item.library
            )
        }
        let creative = plan.creativeSets.filter(\.plan.changesAnything).map { item in
            LibraryPusher.Target(
                id: item.id,
                label: item.label,
                deviceClassID: item.plan.role.rawValue,
                parent: .treatmentLocalization(id: item.treatmentLocalizationID),
                files: item.plan.file.map { [$0.libraryFile] } ?? [],
                slot: item.plan.library
            )
        }
        return screenshotTargets(in: plan) + previews + creative
    }

    private static func screenshotTargets(in plan: ExperimentPlan) -> [LibraryPusher.Target] {
        plan.changingSets.compactMap { item in
            let slot = item.library
            return LibraryPusher.Target(
                id: item.id,
                label: item.label,
                deviceClassID: item.deviceClass.id,
                parent: .treatmentLocalization(id: item.treatmentLocalizationID),
                files: item.localFiles.map(\.libraryFile),
                slot: slot
            )
        }
    }

    /// Pushes through the library and writes the record as each upload lands.
    func pushToLibrary(
        _ targets: [LibraryPusher.Target],
        library: LibraryState,
        at date: Date,
        progress: (@Sendable (ScreenshotPusher.Step) -> Void)?
    ) async -> ScreenshotPusher.Result {
        let project = project
        let pushed = await LibraryPusher(client: client).push(
            targets,
            libraryID: library.libraryID,
            record: library.record,
            saveRecord: { try? AssetRecordStore.save($0, in: project) },
            at: date,
            progress: progress
        )
        try? AssetRecordStore.save(pushed.record, in: project)
        return pushed.result
    }
}

// MARK: - Pruning

/// What a prune deleted, and what App Store Connect refused to delete.
public struct PruneResult: Sendable {
    public var deleted: [RemoteLibraryAsset] = []
    public var refused: [(asset: RemoteLibraryAsset, message: String)] = []
}

public extension PushSession {
    /// Assets nothing places that App Store Connect still lets go.
    ///
    /// Only an asset in Prepare for Submission can be deleted. An approved one
    /// can only be archived, and that stays a person's choice on the website.
    static func pruneCandidates(in library: RemoteAssetLibrary) -> [RemoteLibraryAsset] {
        library.assets.filter {
            $0.state == .prepareForSubmission && (library.placementIDs[$0.id] ?? []).isEmpty
        }
    }

    /// Reads the library and the candidates, and deletes nothing.
    func readPrune(appID: String) async throws -> (library: RemoteAssetLibrary?, candidates: [RemoteLibraryAsset]) {
        guard let library = try await client.readAssetLibrary(appID: appID) else { return (nil, []) }
        return (library, Self.pruneCandidates(in: library))
    }

    /// Deletes the candidates, one at a time. A placement made in the
    /// meantime makes App Store Connect refuse one, and the rest go on.
    func prune(_ candidates: [RemoteLibraryAsset]) async -> PruneResult {
        var result = PruneResult()
        for asset in candidates {
            do {
                try await client.deleteLibraryAsset(media: asset.media, id: asset.id)
                result.deleted.append(asset)
            } catch {
                result.refused.append((asset, "\(error)"))
            }
        }

        // The record forgets what is gone. A record that cannot be read is
        // left alone, the way a push leaves it.
        if result.deleted.isEmpty == false, var record = try? AssetRecordStore.load(in: project) {
            let gone = Set(result.deleted.map(\.id))
            for (md5, entry) in record.assets where gone.contains(entry.assetID) {
                record.forget(md5: md5)
            }
            try? AssetRecordStore.save(record, in: project)
        }
        return result
    }
}
