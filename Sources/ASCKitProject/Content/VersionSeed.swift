import ASCKitAPI
import Foundation

/// Makes the folder for a version App Store Connect opened, holding what App
/// Store Connect put in that version.
///
/// App Store Connect copies the listing of the version before into a new
/// version: the words and the screenshots. An empty folder says the opposite,
/// so the first plan for it removes every screenshot and blanks every field.
/// The folder starts as a copy of what the store holds, and the first plan is
/// empty.
///
/// The words come from the listing. The screenshots come from the older
/// version folders here: each placement names an asset, the record names that
/// asset's checksum, and the checksum finds the file. An image downloaded from
/// App Store Connect is a new encoding with another checksum, so the store
/// would read it as a changed image.
///
/// The copies in `copiesScreenshotsFrom` come last. A language that took the
/// screenshots of the language beside it in an older version takes them in
/// this one too.
public enum VersionSeed {
    /// One screenshot set of the new version.
    public struct Slot: Sendable, Equatable {
        public let locale: String
        public let deviceClass: DeviceClass
        public let count: Int
    }

    public struct Outcome: Sendable {
        public let folder: URL

        /// Languages that got an app information file.
        public var written: [String] = []

        /// Sets copied whole from an older version folder.
        public var copied: [Slot] = []

        /// Sets with at least one image that no folder here holds. Nothing is
        /// copied into those, so the plan names the whole set once.
        public var missing: [Slot] = []

        /// Sets that took the screenshots of the language beside them, because
        /// `copiesScreenshotsFrom` says they do.
        public var fromSibling: [SiblingScreenshots.Remembered] = []
    }

    @discardableResult
    public static func seed(
        version: String,
        from listing: RemoteListing,
        in project: Project
    ) throws -> Outcome {
        let folder = try ContentWriter.createVersion(version, in: project)
        var outcome = Outcome(folder: folder)
        let locales = Set(project.config.writtenLocales)

        // Only the languages the project lists. A language App Store Connect
        // holds and the project does not is what `LocaleAdoption` offers.
        for locale in listing.locales where locales.contains(locale) {
            let information = SnapshotWriter.makeInformation(locale: locale, listing: listing)
            try ContentWriter.writeAppInformation(information, version: version, in: project)
            outcome.written.append(locale)
        }

        let index = FileIndex(project: project, skipping: version)
        let record = (try? AssetRecordStore.load(in: project)) ?? AssetRecord()
        for locale in listing.locales.sorted() where locales.contains(locale) {
            for deviceClass in project.config.resolvedDeviceClasses {
                let placed = LibraryPlanner.current(
                    in: listing.placements, locale: locale,
                    group: deviceClass.placementGroup, type: deviceClass.screenshotPlacementType
                )
                guard placed.isEmpty == false else { continue }

                let slot = Slot(locale: locale, deviceClass: deviceClass, count: placed.count)
                let sources = placed.map { placement in
                    placement.asset.flatMap { record.entry(forAssetID: $0.id) }
                        .flatMap { index.file(md5: $0.md5, size: $0.entry.fileSize) }
                }
                guard sources.allSatisfy({ $0 != nil }) else {
                    outcome.missing.append(slot)
                    continue
                }
                outcome = copy(sources.compactMap(\.self), into: slot, version: version, in: project, outcome)
            }
        }

        // App Store Connect holds a set for each language. A copy that
        // somebody made between two languages and never published is not in
        // the new version, so the setting makes it again here.
        outcome.fromSibling = try SiblingScreenshots.copyRemembered(version: version, in: project)

        // The report names each set once, under what filled it last.
        let taken = outcome.fromSibling
        let tookACopy = { (slot: Slot) in
            taken.contains { $0.locale == slot.locale && $0.deviceClass == slot.deviceClass }
        }
        outcome.copied.removeAll(where: tookACopy)
        outcome.missing.removeAll(where: tookACopy)
        return outcome
    }

    private static func copy(
        _ sources: [URL],
        into slot: Slot,
        version: String,
        in project: Project,
        _ outcome: Outcome
    ) -> Outcome {
        var outcome = outcome
        do {
            try ContentWriter.replaceSlot(
                with: sources, locale: slot.locale, deviceClass: slot.deviceClass, at: .version(version), in: project
            )
            outcome.copied.append(slot)
        } catch {
            outcome.missing.append(slot)
        }
        return outcome
    }
}

// MARK: - Finding a file by checksum

/// Every screenshot in the other version folders, found by size first and by
/// checksum second. A checksum reads the whole file, so only a file of the
/// right size is read.
private final class FileIndex {
    private let bySize: [Int: [URL]]
    private var checksums: [URL: String] = [:]

    init(project: Project, skipping version: String) {
        var bySize: [Int: [URL]] = [:]
        let versions = ((try? project.versionNames()) ?? []).filter { $0 != version }

        // Newest first, so the copy comes from the folder most likely to be
        // the one somebody works in.
        for name in versions.reversed() {
            guard let content = try? ContentStore.load(version: name, in: project) else { continue }
            let slots = content.screenshots.keys.sorted {
                ($0.locale, $0.deviceClassID) < ($1.locale, $1.deviceClassID)
            }
            for slot in slots {
                for file in content.screenshots[slot] ?? [] {
                    bySize[file.byteCount, default: []].append(file.url)
                }
            }
        }
        self.bySize = bySize
    }

    func file(md5: String, size: Int) -> URL? {
        bySize[size]?.first { self.checksum(of: $0) == md5.lowercased() }
    }

    private func checksum(of url: URL) -> String? {
        if let known = checksums[url] { return known }
        let computed = try? FileChecksum.md5(of: url)
        checksums[url] = computed
        return computed
    }
}
