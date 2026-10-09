import ASCKitAPI
import Foundation

// MARK: - On disk

/// The product page header or the search results art of one language: an
/// image or a video.
public struct CreativeFile: Sendable, Hashable {
    public let url: URL
    public let fileName: String
    public let byteCount: Int
    public let media: LibraryMedia
    public let pixelWidth: Int?
    public let pixelHeight: Int?
    public let hasAlpha: Bool?
    public let duration: Double?
    public let frameRate: Double?

    public static func inspect(url: URL) -> CreativeFile {
        let ext = url.pathExtension.lowercased()
        if CreativeFolder.videoExtensions.contains(ext) {
            let video = VideoInspector.inspect(url: url)
            return CreativeFile(url: url, fileName: video.fileName, byteCount: video.byteCount, media: .video,
                                pixelWidth: video.pixelWidth, pixelHeight: video.pixelHeight, hasAlpha: nil,
                                duration: video.duration, frameRate: video.frameRate)
        }
        let image = ImageInspector.inspect(url: url)
        return CreativeFile(url: url, fileName: image.fileName, byteCount: image.byteCount, media: .image,
                            pixelWidth: image.pixelWidth, pixelHeight: image.pixelHeight, hasAlpha: image.hasAlpha,
                            duration: nil, frameRate: nil)
    }

    public var libraryFile: LibraryFile {
        LibraryFile(url: url, fileName: fileName, byteCount: byteCount, media: media, category: .creativeAssets)
    }
}

/// Where the art goes. Each is one placement on a language.
public enum CreativeRole: String, Sendable, CaseIterable, Hashable {
    case header
    case searchResults = "search-results"

    public var placementType: PlacementType {
        switch self {
        case .header: .productPageHeader
        case .searchResults: .searchResults
        }
    }

    /// App Store Connect's one group for this art, on every device.
    public static let group = "DEFAULT_PROFILE"
}

/// `creative/<locale>/header.png` and `creative/<locale>/search-results.mov`,
/// for a version or for a treatment of a test.
public struct CreativeFolder: Sendable {
    public static let folderName = "creative"
    static let videoExtensions: Set = ["mov", "mp4", "m4v"]
    static let imageExtensions: Set = ["png", "jpg", "jpeg"]

    /// By locale, then by role. A role with two files, such as `header.png`
    /// and `header.mov`, keeps both, so the check can say so.
    public var files: [String: [CreativeRole: [CreativeFile]]] = [:]

    /// Files whose name is no role, by locale.
    public var strays: [String: [String]] = [:]

    public init() {}

    public static func load(from root: URL) -> CreativeFolder {
        var folder = CreativeFolder()
        for localeURL in DirectoryListing.directories(in: root) {
            let locale = localeURL.lastPathComponent
            let entries = DirectoryListing.entries(in: localeURL, keys: [])
            for url in entries.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                guard let role = CreativeRole(rawValue: url.deletingPathExtension().lastPathComponent) else {
                    folder.strays[locale, default: []].append(url.lastPathComponent)
                    continue
                }
                folder.files[locale, default: [:]][role, default: []].append(CreativeFile.inspect(url: url))
            }
        }
        return folder
    }

    public func file(locale: String, role: CreativeRole) -> CreativeFile? {
        files[locale]?[role]?.first
    }

    public var isEmpty: Bool { files.isEmpty && strays.isEmpty }
}

public extension Project {
    func creativeURL(version: String) -> URL {
        versionsURL.appending(path: version).appending(path: CreativeFolder.folderName)
    }
}

// MARK: - The plan

/// One role on one language: what the library holds, and what the file says.
public struct CreativePlan: Sendable, Identifiable {
    public let locale: String
    public let role: CreativeRole
    public let file: CreativeFile?

    /// True when the search results show the header's asset.
    public let usesHeader: Bool

    /// The language whose file this one shows, or nil when it shows its own.
    public let shownFrom: String?
    public let library: LibrarySlot

    public var id: String { "\(locale)|\(role.rawValue)" }
    public var changesAnything: Bool { library.isUnchanged == false }
    public var action: ChangePlan.ScreenshotPlan.Action { LibraryPlanner.action(for: library) }
}

public enum CreativePlanner {
    /// The roles of every language, against the placements of `DEFAULT_PROFILE`.
    ///
    /// A language with no file for a role and no placement for it is left out.
    /// A placement with no file is removed, the way a screenshot is. A
    /// language with a header and no search results file shows the header
    /// in search results too.
    ///
    /// `sources` names the language whose files a language shows, for a
    /// language with no files of its own.
    public static func plans(
        folder: CreativeFolder,
        locales: [String],
        placements: [RemotePlacement],
        record: AssetRecord,
        sources: [String: String] = [:]
    ) -> [CreativePlan] {
        var plans: [CreativePlan] = []
        for locale in locales.sorted() {
            let hasOwn = folder.files[locale]?.isEmpty == false
            let shownFrom = hasOwn ? nil : sources[locale]
            let shown = shownFrom ?? locale

            for role in CreativeRole.allCases {
                var file = folder.file(locale: shown, role: role)
                var usesHeader = false
                if role == .searchResults, file == nil {
                    file = folder.file(locale: shown, role: .header)
                    usesHeader = file != nil
                }

                let current = LibraryPlanner.current(
                    in: placements, locale: locale, group: CreativeRole.group, type: role.placementType
                )
                guard file != nil || current.isEmpty == false else { continue }

                plans.append(CreativePlan(
                    locale: locale,
                    role: role,
                    file: file,
                    usesHeader: usesHeader,
                    shownFrom: file == nil ? nil : shownFrom,
                    library: LibraryPlanner.slot(
                        files: file.map { [$0.libraryFile] } ?? [], current: current, record: record,
                        group: CreativeRole.group, type: role.placementType
                    )
                ))
            }
        }
        return plans
    }
}
