import ASCKitAPI
import Foundation

/// A file on disk that goes into the library: a screenshot or an app preview.
public struct LibraryFile: Sendable, Hashable {
    public let url: URL
    public let fileName: String
    public let byteCount: Int
    public let media: LibraryMedia

    /// The poster frame of a video, such as `00:00:05:00`. Nil leaves the one
    /// App Store Connect has.
    public let posterFrame: String?

    /// Screenshots and previews, or the header and search results art.
    public let category: LibraryAssetCategory

    public init(
        url: URL,
        fileName: String,
        byteCount: Int,
        media: LibraryMedia,
        posterFrame: String? = nil,
        category: LibraryAssetCategory = .screenshotsAndPreviews
    ) {
        self.url = url
        self.fileName = fileName
        self.byteCount = byteCount
        self.media = media
        self.posterFrame = posterFrame
        self.category = category
    }
}

public extension ScreenshotFile {
    var libraryFile: LibraryFile {
        LibraryFile(url: url, fileName: fileName, byteCount: byteCount, media: .image)
    }
}

public extension PreviewFile {
    var libraryFile: LibraryFile {
        LibraryFile(url: url, fileName: fileName, byteCount: byteCount, media: .video, posterFrame: posterFrame)
    }
}

/// How one slot of the library compares with the files on disk.
///
/// A slot is one group of one placement type on one language, such as the 6.9
/// inch iPhone screenshots of en-US. Placements that already hold the right
/// asset stay, so a push sends only what changed.
public struct LibrarySlot: Sendable, Equatable {
    public let group: String
    public let type: PlacementType

    /// One for each local file, in file name order: the asset that already
    /// holds its bytes, or nil when the file has to go up first.
    public let wanted: [String?]

    /// The MD5 of each local file, in the same order. Nil when the file could
    /// not be read.
    public let checksums: [String?]

    /// What App Store Connect holds in the slot now, in the store's order.
    public let current: [RemotePlacement]

    /// The poster frame to set on a video the slot keeps, by asset id. A video
    /// that goes up new takes its poster frame with it.
    public let posterFrames: [String: String]

    public init(
        group: String,
        type: PlacementType,
        wanted: [String?],
        checksums: [String?],
        current: [RemotePlacement],
        posterFrames: [String: String] = [:]
    ) {
        self.group = group
        self.type = type
        self.wanted = wanted
        self.checksums = checksums
        self.current = current
        self.posterFrames = posterFrames
    }

    /// The placements that already hold a wanted asset, by asset id. Each
    /// asset is kept as many times as it is wanted, the first ones first.
    public var kept: [RemotePlacement] {
        var needed = Dictionary(wanted.compactMap(\.self).map { ($0, 1) }, uniquingKeysWith: +)
        return current.filter { placement in
            guard let id = placement.asset?.id, let count = needed[id], count > 0 else { return false }
            needed[id] = count - 1
            return true
        }
    }

    public var toRemove: [RemotePlacement] {
        let keptIDs = Set(kept.map(\.id))
        return current.filter { keptIDs.contains($0.id) == false }
    }

    public var placementsToAdd: Int { wanted.count - kept.count }

    /// Files whose bytes no asset holds yet.
    public var uploads: Int { wanted.filter { $0 == nil }.count }

    public var isUnchanged: Bool {
        wanted.allSatisfy { $0 != nil } && wanted == current.map(\.asset?.id) && posterFrames.isEmpty
    }
}

public enum LibraryPlanner {
    /// Compares the files of one slot with its placements.
    ///
    /// A file counts as there when the record names an asset with its bytes
    /// and App Store Connect can still place that asset. An asset that failed
    /// or was archived goes up again.
    public static func slot(
        files: [LibraryFile],
        current: [RemotePlacement],
        record: AssetRecord,
        group: String,
        type: PlacementType
    ) -> LibrarySlot {
        let states = Dictionary(
            current.compactMap { placement in placement.asset.map { ($0.id, $0.state) } },
            uniquingKeysWith: { first, _ in first }
        )

        let timeCodes = Dictionary(
            current.compactMap { placement in placement.asset.map { ($0.id, $0.previewFrameTimeCode) } },
            uniquingKeysWith: { first, _ in first }
        )

        var wanted: [String?] = []
        var checksums: [String?] = []
        var posterFrames: [String: String] = [:]
        for file in files {
            let md5 = try? FileChecksum.md5(of: file.url)
            checksums.append(md5)

            guard let md5, let id = record.assetID(md5: md5, fileSize: file.byteCount) else {
                wanted.append(nil)
                continue
            }
            let state: LibraryAssetState? = states[id] ?? record.entry(forAssetID: id)?.entry.state
            guard isUsable(state) else {
                wanted.append(nil)
                continue
            }
            wanted.append(id)

            // Compared only where the slot shows the video's time code. A video
            // placed nowhere here has none to compare with.
            if let posterFrame = file.posterFrame, let shown = timeCodes[id], shown != posterFrame {
                posterFrames[id] = posterFrame
            }
        }
        return LibrarySlot(
            group: group, type: type, wanted: wanted, checksums: checksums,
            current: current, posterFrames: posterFrames
        )
    }

    /// The placements of one slot, from all the placements of one language.
    public static func current(
        in placements: [RemotePlacement],
        locale: String,
        group: String,
        type: PlacementType
    ) -> [RemotePlacement] {
        placements.filter { $0.locale == locale && $0.group == group && $0.type == type }
    }

    /// The action a slot shows in a plan. Removing counts the placements that
    /// go, and adding the placements that come, whether or not their file
    /// is already in the library.
    public static func action(for slot: LibrarySlot) -> ChangePlan.ScreenshotPlan.Action {
        slot.isUnchanged ? .unchanged : .replace(removing: slot.toRemove.count, adding: slot.placementsToAdd)
    }

    /// Placements whose asset App Store Connect is still processing. A plan
    /// worked out from them can change once it finishes.
    public static func stillArriving(_ slot: LibrarySlot) -> [RemotePlacement] {
        slot.current.filter { $0.asset?.state?.isProcessing == true || $0.state == .assetProcessing }
    }

    private static func isUsable(_ state: LibraryAssetState?) -> Bool {
        guard let state else { return true }
        return state != .failed && state != .archived
    }
}
