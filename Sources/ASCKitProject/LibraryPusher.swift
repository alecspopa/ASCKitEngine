import ASCKitAPI
import Foundation

/// Puts the screenshots of a plan into the App Asset Library and places them.
///
/// It works in this order, for the whole push at once:
/// 1. Upload each file the library does not hold, once, however many
///    languages and slots use it. Each commit goes into the record straight
///    away, so a push that stops halfway keeps what it sent.
/// 2. Wait until App Store Connect has processed the new assets.
/// 3. In each slot, delete the placements that are not wanted, make the ones
///    that are missing, and set the order.
///
/// Removing a placement leaves its asset in the library, so nothing a push
/// does here loses an image.
public struct LibraryPusher: Sendable {
    /// One slot to fill, with the parent its placements go on.
    public struct Target: Sendable {
        public let id: String
        public let label: String
        public let deviceClassID: String
        public let parent: PlacementParent
        public let files: [LibraryFile]
        public let slot: LibrarySlot

        public init(
            id: String,
            label: String,
            deviceClassID: String,
            parent: PlacementParent,
            files: [LibraryFile],
            slot: LibrarySlot
        ) {
            self.id = id
            self.label = label
            self.deviceClassID = deviceClassID
            self.parent = parent
            self.files = files
            self.slot = slot
        }
    }

    private let client: ASCClient
    private let poll: LibraryUploader.PollSettings
    private let uploadLimit: Int

    init(
        client: ASCClient,
        poll: LibraryUploader.PollSettings = LibraryUploader.PollSettings(),
        uploadLimit: Int = LibraryUploader.defaultLimit
    ) {
        self.client = client
        self.poll = poll
        self.uploadLimit = uploadLimit
    }

    /// The result, and the record with every asset this push made in it.
    func push(
        _ targets: [Target],
        libraryID: String,
        record: AssetRecord,
        saveRecord: @escaping @Sendable (AssetRecord) -> Void,
        at date: Date = .now,
        progress: (@Sendable (ScreenshotPusher.Step) -> Void)? = nil
    ) async -> (result: ScreenshotPusher.Result, record: AssetRecord) {
        let box = RecordBox(record, uploadedAt: date)
        var result = ScreenshotPusher.Result()

        let uploads = Self.uploads(in: targets)
        let failedUploads = await upload(uploads, libraryID: libraryID, box: box, saveRecord: saveRecord,
                                         progress: progress)

        let processed = await waitForProcessing(box: box, libraryID: libraryID, md5s: Array(uploads.keys))

        for target in targets {
            do {
                let ids = try await resolve(target, box: box, failedUploads: failedUploads, processed: processed)
                let placed = try await place(ids, in: target, progress: progress)
                result.uploaded.append(target.id)
                result.slots.append(ScreenshotPusher.SlotWritten(
                    slot: target.id,
                    assetIDs: ids,
                    placementIDs: placed.placementIDs,
                    removedPlacementIDs: placed.removed,
                    uploadedAssetIDs: zip(ids, target.slot.wanted).compactMap { $1 == nil ? $0 : nil }
                ))
            } catch {
                result.failed.append(ScreenshotPusher.Failure(
                    locale: target.label,
                    deviceClassID: target.deviceClassID,
                    message: Self.describe(error, target: target)
                ))
            }
        }
        return await (result, box.record)
    }

    // MARK: - Uploads

    /// One file for each MD5 that no asset holds, with the first slot that
    /// wants it, for the progress line.
    static func uploads(in targets: [Target]) -> [String: (file: LibraryFile, target: Target)] {
        var uploads: [String: (file: LibraryFile, target: Target)] = [:]
        for target in targets {
            for (index, assetID) in target.slot.wanted.enumerated() where assetID == nil {
                guard let md5 = target.slot.checksums[index], uploads[md5] == nil else { continue }
                uploads[md5] = (target.files[index], target)
            }
        }
        return uploads
    }

    /// The MD5s whose upload failed, with the reason.
    private func upload(
        _ uploads: [String: (file: LibraryFile, target: Target)],
        libraryID: String,
        box: RecordBox,
        saveRecord: @escaping @Sendable (AssetRecord) -> Void,
        progress: (@Sendable (ScreenshotPusher.Step) -> Void)?
    ) async -> [String: String] {
        guard uploads.isEmpty == false else { return [:] }

        var byURL: [URL: (md5: String, size: Int)] = [:]
        var byName: [String: Target] = [:]
        var items: [LibraryUploader.Item] = []
        for (md5, upload) in uploads.sorted(by: { $0.value.file.fileName < $1.value.file.fileName }) {
            byURL[upload.file.url] = (md5, upload.file.byteCount)
            byName[upload.file.fileName] = byName[upload.file.fileName] ?? upload.target
            items.append(LibraryUploader.Item(
                fileURL: upload.file.url,
                media: upload.file.media,
                category: upload.file.category,
                referenceName: upload.file.fileName,
                previewFrameTimeCode: upload.file.posterFrame
            ))
        }

        let lookup = byURL
        let targets = byName
        let results = await LibraryUploader(client: client).upload(
            items,
            libraryID: libraryID,
            limit: uploadLimit,
            progress: { step in
                guard step.step == .reserving, let target = targets[step.fileName] else { return }
                progress?(.uploading(locale: target.label, deviceClass: target.deviceClassID, fileName: step.fileName))
            },
            onCommit: { committed in
                guard let (md5, size) = lookup[committed.item.fileURL] else { return }
                let entry = AssetRecord.Entry(
                    assetID: committed.assetID,
                    media: committed.item.media,
                    category: committed.item.category,
                    fileName: committed.item.fileName,
                    fileSize: size,
                    uploadedAt: nil,
                    state: .uploadComplete
                )
                await saveRecord(box.record(md5: md5, entry))
            }
        )

        var failed: [String: String] = [:]
        for (item, outcome) in results {
            if case let .failure(error) = outcome, let md5 = lookup[item.fileURL]?.md5 {
                failed[md5] = "\(error)"
            }
        }
        return failed
    }

    /// The state of every asset this push uploaded, after the wait.
    private func waitForProcessing(
        box: RecordBox,
        libraryID: String,
        md5s: [String]
    ) async -> [String: Resource<LibraryAssetAttributes>] {
        let record = await box.record
        let ids = md5s.compactMap { record.assets[$0] }
        guard ids.isEmpty == false else { return [:] }

        let byMedia = Dictionary(grouping: ids, by: \.media).mapValues { $0.map(\.assetID) }
        let states = await (try? LibraryUploader(client: client)
            .waitUntilProcessed(byMedia, libraryID: libraryID, poll: poll)) ?? [:]
        await box.update(states: states.compactMapValues { $0.attributes?.state })
        return states
    }

    // MARK: - One slot

    /// The asset id of each file, now that the uploads are done.
    private func resolve(
        _ target: Target,
        box: RecordBox,
        failedUploads: [String: String],
        processed: [String: Resource<LibraryAssetAttributes>]
    ) async throws -> [String] {
        let record = await box.record
        var ids: [String] = []
        for (index, wanted) in target.slot.wanted.enumerated() {
            if let wanted {
                ids.append(wanted)
                continue
            }
            let file = target.files[index]
            guard let md5 = target.slot.checksums[index] else {
                throw LibraryPushError.unreadable(fileName: file.fileName)
            }
            if let reason = failedUploads[md5] {
                throw LibraryPushError.uploadFailed(fileName: file.fileName, reason: reason)
            }
            guard let id = record.assetID(md5: md5, fileSize: file.byteCount)
                ?? record.assets[md5]?.assetID
            else {
                throw LibraryPushError.uploadFailed(fileName: file.fileName, reason: nil)
            }
            if let asset = processed[id], let state = asset.attributes?.state {
                if state == .failed {
                    throw LibraryUploader.Committed.failure(fileName: file.fileName, asset: asset)
                }
                if state.isProcessing {
                    throw UploadError.stillProcessing(fileName: file.fileName, afterAttempts: poll.attempts)
                }
            }
            ids.append(id)
        }
        return ids
    }

    /// Deletes what is not wanted, makes what is missing, and sets the order.
    /// Gives the placements of the slot in order, and the ones it deleted.
    private func place(
        _ ids: [String],
        in target: Target,
        progress: (@Sendable (ScreenshotPusher.Step) -> Void)?
    ) async throws -> (placementIDs: [String], removed: [String]) {
        let wanted = LibrarySlot(
            group: target.slot.group,
            type: target.slot.type,
            wanted: ids,
            checksums: target.slot.checksums,
            current: target.slot.current,
            posterFrames: target.slot.posterFrames
        )
        if wanted.isUnchanged { return (target.slot.current.map(\.id), []) }

        for (videoID, timeCode) in wanted.posterFrames.sorted(by: { $0.key < $1.key }) {
            _ = try await client.setPreviewFrame(videoID: videoID, timeCode: timeCode)
        }

        let removing = wanted.toRemove
        if removing.isEmpty == false {
            progress?(.removing(locale: target.label, deviceClass: target.deviceClassID, count: removing.count))
            for placement in removing {
                try await client.deletePlacement(id: placement.id)
            }
        }

        // Each kept placement stands for one wanted asset, in the store's order.
        var keptByAsset: [String: [String]] = [:]
        for placement in wanted.kept {
            if let id = placement.asset?.id { keptByAsset[id, default: []].append(placement.id) }
        }

        if wanted.placementsToAdd > 0 {
            progress?(.placing(locale: target.label, deviceClass: target.deviceClassID, count: wanted.placementsToAdd))
        }
        var ordered: [String] = []
        for (index, assetID) in ids.enumerated() {
            if let placementID = keptByAsset[assetID]?.first {
                keptByAsset[assetID]?.removeFirst()
                ordered.append(placementID)
                continue
            }
            let made = try await client.createPlacement(
                type: target.slot.type,
                group: target.slot.group,
                media: target.files[index].media,
                assetID: assetID,
                on: target.parent
            )
            ordered.append(made.id)
        }

        // Nothing moved when only a poster frame changed.
        let unmoved = removing.isEmpty && ordered == target.slot.current.map(\.id)
        let removed = removing.map(\.id)
        guard ordered.count > 1, unmoved == false else { return (ordered, removed) }
        progress?(.ordering(locale: target.label, deviceClass: target.deviceClassID))
        try await client.orderPlacements(group: target.slot.group, on: target.parent, orderedIDs: ordered)
        return (ordered, removed)
    }

    private static func describe(_ error: any Error, target: Target) -> String {
        switch LibraryRefusal(error) {
        case .parentStateForbids:
            String(localized: """
            App Store Connect does not take changes to \(target.label) in its current state. \
            Nothing in this slot changed after the refusal.
            """, bundle: .module)
        case .placementNotSupported:
            String(localized: """
            App Store Connect does not take these images in \(target.slot.group). \
            Check that their size fits \(target.deviceClassID).
            """, bundle: .module)
        default:
            "\(error)"
        }
    }
}

/// The record, shared by uploads that finish at the same time.
actor RecordBox {
    private(set) var record: AssetRecord

    /// When this push uploaded, for each entry it adds.
    private let uploadedAt: Date

    init(_ record: AssetRecord, uploadedAt: Date) {
        self.record = record
        self.uploadedAt = uploadedAt
    }

    func record(md5: String, _ entry: AssetRecord.Entry) -> AssetRecord {
        var dated = entry
        dated.uploadedAt = uploadedAt
        record.record(md5: md5, dated)
        return record
    }

    func update(states: [String: LibraryAssetState]) {
        for (md5, entry) in record.assets {
            guard let state = states[entry.assetID] else { continue }
            var changed = entry
            changed.state = state
            record.record(md5: md5, changed)
        }
    }
}

public enum LibraryPushError: Error, CustomLocalizedStringResourceConvertible {
    case unreadable(fileName: String)
    case uploadFailed(fileName: String, reason: String?)

    public var localizedStringResource: LocalizedStringResource {
        switch self {
        case let .unreadable(fileName):
            LocalizedStringResource("ASCKit could not read \(fileName), so it did not upload it.", bundle: .here)
        case let .uploadFailed(fileName, reason?):
            LocalizedStringResource("\(fileName) did not upload. \(reason)", bundle: .here)
        case let .uploadFailed(fileName, nil):
            LocalizedStringResource("\(fileName) did not upload.", bundle: .here)
        }
    }
}

extension LibraryPushError: CustomStringConvertible {
    public var description: String { String(localized: localizedStringResource) }
}
