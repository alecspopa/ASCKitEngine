import ASCKitAPI
import Foundation

/// What this project uploaded into the app's library, by the MD5 of each file.
///
/// The library keeps no checksum, so this record is what says that a local
/// file is already there. It lives in the project and goes into git, so that
/// every clone knows the same uploads.
public struct AssetRecord: Codable, Sendable, Equatable {
    /// By the MD5 of the file, in lower case hex. Two files with the same bytes
    /// share one entry, and one upload.
    public private(set) var assets: [String: Entry]

    public struct Entry: Codable, Sendable, Equatable {
        public var assetID: String
        public var media: LibraryMedia
        public var category: LibraryAssetCategory?
        public var fileName: String
        public var fileSize: Int
        public var uploadedAt: Date?
        public var state: LibraryAssetState?

        public init(
            assetID: String,
            media: LibraryMedia,
            category: LibraryAssetCategory? = nil,
            fileName: String,
            fileSize: Int,
            uploadedAt: Date? = nil,
            state: LibraryAssetState? = nil
        ) {
            self.assetID = assetID
            self.media = media
            self.category = category
            self.fileName = fileName
            self.fileSize = fileSize
            self.uploadedAt = uploadedAt
            self.state = state
        }
    }

    public init(assets: [String: Entry] = [:]) {
        self.assets = assets
    }

    public var isEmpty: Bool { assets.isEmpty }

    /// The asset that holds a file with these bytes.
    ///
    /// The size has to match as well. A record edited by hand, or merged
    /// badly, can name an MD5 with another file's size, and then the entry
    /// says nothing that can be trusted.
    public func assetID(md5: String, fileSize: Int) -> String? {
        guard let entry = assets[md5.lowercased()], entry.fileSize == fileSize else { return nil }
        return entry.assetID
    }

    public func entry(forAssetID id: String) -> (md5: String, entry: Entry)? {
        assets.first { $0.value.assetID == id }.map { ($0.key, $0.value) }
    }

    public mutating func record(md5: String, _ entry: Entry) {
        assets[md5.lowercased()] = entry
    }

    public mutating func forget(md5: String) {
        assets[md5.lowercased()] = nil
    }

    /// Drops the entries whose asset App Store Connect no longer has, and
    /// keeps the state it reported for the rest.
    public mutating func keepOnly(_ library: RemoteAssetLibrary) {
        let states = Dictionary(library.assets.map { ($0.id, $0.state) }, uniquingKeysWith: { first, _ in first })
        assets = assets.compactMapValues { entry in
            guard let state = states[entry.assetID] else { return nil }
            var kept = entry
            kept.state = state ?? entry.state
            return kept
        }
    }
}

// MARK: - From the old screenshot sets

public extension AssetRecord {
    /// Fills the record from screenshots sent with the old endpoints.
    ///
    /// App Store Connect moved every old screenshot into the library, and each
    /// set shows up as placements in the same order. An old screenshot has a
    /// checksum and its placement has the asset id, so the two side by side
    /// say which asset holds which bytes. A pair is used only when the file
    /// names match, so a set and a group that disagree add nothing.
    ///
    /// An entry already in the record stays as it is.
    mutating func adopt(sets: [RemoteScreenshotSet], placements: [RemotePlacement]) {
        for set in sets {
            guard let deviceClass = DeviceClass.all.first(where: { $0.displayType == set.displayType }) else { continue }
            let placed = placements.filter {
                $0.locale == set.locale
                    && $0.group == deviceClass.placementGroup
                    && $0.type == deviceClass.screenshotPlacementType
            }
            for (shot, placement) in zip(set.screenshots, placed) {
                guard let md5 = shot.sourceFileChecksum?.lowercased(),
                      assets[md5] == nil,
                      let asset = placement.asset,
                      let fileName = shot.fileName,
                      fileName == asset.fileName
                else { continue }

                assets[md5] = Entry(
                    assetID: asset.id,
                    media: asset.media,
                    category: asset.category,
                    fileName: fileName,
                    fileSize: asset.fileSize ?? shot.fileSize ?? 0,
                    state: asset.state
                )
            }
        }
    }
}

// MARK: - On disk

public enum AssetRecordStore {
    public static let fileName = "asset-library.json"

    public static func url(in project: Project) -> URL {
        project.rootURL.appending(path: fileName)
    }

    /// An empty record when there is no file yet, or an empty one.
    ///
    /// A damaged file throws rather than reading as empty. Read as empty, the
    /// next push would upload every file again and then write over the record.
    public static func load(in project: Project) throws -> AssetRecord {
        let url = url(in: project)
        guard let data = try? Data(contentsOf: url) else { return AssetRecord() }
        let text = String(bytes: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let text, text.isEmpty { return AssetRecord() }

        do {
            return try decoder.decode(AssetRecord.self, from: data)
        } catch {
            throw AssetRecordError.damaged(path: url.path)
        }
    }

    /// Written whole to a temporary file and then moved, so a write that
    /// fails leaves the old record as it was.
    public static func save(_ record: AssetRecord, in project: Project) throws {
        try ProjectJSON.write(record, to: url(in: project), datesAsISO8601: true, atomic: true)
    }

    private static var decoder: JSONDecoder { ProjectJSON.decoder(datesAsISO8601: true) }
}

public enum AssetRecordError: Error, Equatable, CustomLocalizedStringResourceConvertible {
    case damaged(path: String)

    public var localizedStringResource: LocalizedStringResource {
        switch self {
        case let .damaged(path):
            LocalizedStringResource("""
            ASCKit cannot read \(path). It records what this project uploaded to App Store \
            Connect. Fix the file, or take it back from git. ASCKit does not write over it.
            """, bundle: .here)
        }
    }
}

extension AssetRecordError: CustomStringConvertible {
    public var description: String { String(localized: localizedStringResource) }
}
