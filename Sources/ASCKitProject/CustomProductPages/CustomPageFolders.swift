import ASCKitAPI
import Foundation

/// Where the text and the images of a custom product page live.
///
///     custom-product-pages/
///     └── Night sky/                 the page, named as App Store Connect names it
///         ├── page.json              the deep link
///         ├── text/
///         │   └── en-US.json         the promotional text and the keywords
///         ├── en-US/
///         │   └── iphone-6.9/
///         │       └── 01-moon-iPhone-6.9-en_US.png
///         ├── previews/en-US/iphone-6.9/
///         └── creative/en-US/header.png
///
/// Beside `versions`, not inside one, for the reason a test is: a page belongs
/// to the app, not to a release.
///
/// ASCKit never makes a page, a version of a page or a language of a page on
/// App Store Connect. They are made there, and a folder here only holds what
/// goes into them.
public enum CustomPageFolders {
    public static let folderName = "custom-product-pages"
    public static let textFolderName = "text"
    public static let settingsFileName = "page.json"

    /// No language code is one of these, so the names are free.
    static let reservedNames: Set = [textFolderName, Project.previewsFolderName, CreativeFolder.folderName]

    /// The folder name of each page, keyed by its id.
    public static func folderNames(for remote: RemoteCustomPages) -> [String: String] {
        FolderNaming.folderNames(for: remote.pages.map { ($0.id, $0.name) })
    }

    /// Makes the empty folders a person drops images into, for every language
    /// of every page that takes changes. Returns the folders it made.
    ///
    /// Only the iPhone and iPad device classes, because a custom product page
    /// is only on the iOS App Store.
    @discardableResult
    public static func scaffold(_ remote: RemoteCustomPages, in project: Project) throws -> [URL] {
        var made: [URL] = []
        let deviceClasses = project.config.resolvedDeviceClasses.filter { $0.platform == .ios }
        let names = folderNames(for: remote)

        for page in remote.pages where page.isEditable {
            for localization in page.version?.localizations ?? [] {
                for deviceClass in deviceClasses {
                    let url = project.customPageURL(
                        page: names[page.id] ?? page.name,
                        locale: localization.locale,
                        deviceClassID: deviceClass.id
                    )
                    guard FileManager.default.fileExists(atPath: url.path) == false else { continue }
                    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                    made.append(url)
                }
            }
        }
        return made
    }

    /// Writes what App Store Connect holds into the text files that are not
    /// there yet, so the first plan of a page is empty.
    ///
    /// A file that is there is never written over. It holds what a person
    /// wants, and the plan says how that differs.
    @discardableResult
    public static func seed(_ remote: RemoteCustomPages, in project: Project) throws -> [URL] {
        var written: [URL] = []
        let names = folderNames(for: remote)

        for page in remote.pages where page.isEditable {
            guard let version = page.version else { continue }
            let folder = names[page.id] ?? page.name

            let settingsURL = project.customPageSettingsURL(page: folder)
            if let deepLink = version.deepLink, FileManager.default.fileExists(atPath: settingsURL.path) == false {
                try write(CustomPageSettings(deepLink: deepLink), to: settingsURL)
                written.append(settingsURL)
            }

            for localization in version.localizations {
                let url = project.customPageTextURL(page: folder, locale: localization.locale)
                guard FileManager.default.fileExists(atPath: url.path) == false else { continue }
                // No keywords is written as nothing, not as an empty list.
                // An empty list unlinks every keyword, so one linked later in
                // App Store Connect would go on the next push.
                try write(CustomPageText(
                    locale: localization.locale,
                    promotionalText: localization.promotionalText,
                    keywords: localization.keywordIDs.isEmpty ? nil : localization.keywordIDs
                ), to: url)
                written.append(url)
            }
        }
        return written
    }

    static func write(_ value: some Encodable, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try ProjectJSON.write(value, to: url, atomic: true)
    }
}

public extension Project {
    var customPagesURL: URL { rootURL.appending(path: CustomPageFolders.folderName) }

    func customPageURL(page: String) -> URL {
        customPagesURL.appending(path: page)
    }

    func customPageURL(page: String, locale: String, deviceClassID: String) -> URL {
        customPageURL(page: page).appending(path: locale).appending(path: deviceClassID)
    }

    func customPageTextURL(page: String, locale: String) -> URL {
        customPageURL(page: page)
            .appending(path: CustomPageFolders.textFolderName)
            .appending(path: "\(locale).json")
    }

    func customPageSettingsURL(page: String) -> URL {
        customPageURL(page: page).appending(path: CustomPageFolders.settingsFileName)
    }
}

// MARK: - The files

/// The words of one language of a page, in `text/<locale>.json`.
///
/// A field left out is left alone on App Store Connect. An empty string is
/// never written.
public struct CustomPageText: Codable, Sendable, Equatable {
    public var locale: String
    public var promotionalText: String?

    /// The keywords linked to this language, from the keywords of the version
    /// on sale. Nil leaves the links alone. An empty list unlinks them all.
    public var keywords: [String]?

    public init(locale: String, promotionalText: String? = nil, keywords: [String]? = nil) {
        self.locale = locale
        self.promotionalText = promotionalText
        self.keywords = keywords
    }
}

/// What belongs to the whole page rather than to one language, in `page.json`.
public struct CustomPageSettings: Codable, Sendable, Equatable {
    /// Where the app opens from this page. Nil leaves it alone.
    public var deepLink: String?

    public init(deepLink: String? = nil) {
        self.deepLink = deepLink
    }
}

// MARK: - On disk

/// One folder of images, named by the page, the language and the device class.
public struct CustomPageSlot: Sendable, Hashable {
    /// A folder name, not an id. A folder is what a person sees.
    public let page: String
    public let locale: String
    public let deviceClassID: String

    public init(page: String, locale: String, deviceClassID: String) {
        self.page = page
        self.locale = locale
        self.deviceClassID = deviceClassID
    }

    /// The folder of this slot, below the pages folder.
    public var path: String { "\(page)/\(locale)/\(deviceClassID)" }
}

/// Everything the `custom-product-pages` folder holds, read and not yet
/// checked.
public struct CustomPageContent: Sendable {
    public var screenshots: [CustomPageSlot: [ScreenshotFile]] = [:]

    /// From `<page>/previews/<locale>/<device class>/`.
    public var previews: [CustomPageSlot: [PreviewFile]] = [:]

    /// From `<page>/creative/<locale>/`, by page folder.
    public var creative: [String: CreativeFolder] = [:]

    /// From `<page>/text/<locale>.json`, by page folder, then by language.
    public var texts: [String: [String: CustomPageText]] = [:]

    /// From `<page>/page.json`, by page folder.
    public var settings: [String: CustomPageSettings] = [:]

    /// Files that are there and could not be read, with the reason.
    public var unreadable: [URL: String] = [:]

    public init() {}

    public func screenshots(in slot: CustomPageSlot) -> [ScreenshotFile] {
        screenshots[slot] ?? []
    }

    public func previews(in slot: CustomPageSlot) -> [PreviewFile] {
        previews[slot] ?? []
    }

    public func text(page: String, locale: String) -> CustomPageText? {
        texts[page]?[locale]
    }

    /// The page folders found, whatever App Store Connect holds.
    public var pageFolders: Set<String> {
        Set(screenshots.keys.map(\.page)).union(texts.keys).union(settings.keys)
    }
}

public enum CustomPageContentStore {
    public static func load(in project: Project) -> CustomPageContent {
        var content = CustomPageContent()

        for page in DirectoryListing.directories(in: project.customPagesURL) {
            let folder = page.lastPathComponent
            loadImages(of: page, into: &content)

            let settingsURL = page.appending(path: CustomPageFolders.settingsFileName)
            if FileManager.default.fileExists(atPath: settingsURL.path) {
                do {
                    content.settings[folder] = try read(CustomPageSettings.self, from: settingsURL)
                } catch {
                    content.unreadable[settingsURL] = "\(error)"
                }
            }

            let textFolder = page.appending(path: CustomPageFolders.textFolderName)
            for url in DirectoryListing.files(in: textFolder) where url.pathExtension == "json" {
                do {
                    let text = try read(CustomPageText.self, from: url)
                    content.texts[folder, default: [:]][text.locale] = text
                } catch {
                    content.unreadable[url] = "\(error)"
                }
            }
        }
        return content
    }

    private static func loadImages(of page: URL, into content: inout CustomPageContent) {
        let folder = page.lastPathComponent

        let previews = PreviewFolder.load(from: page.appending(path: Project.previewsFolderName))
        for (slot, files) in previews.previews {
            content.previews[CustomPageSlot(page: folder, locale: slot.locale, deviceClassID: slot.deviceClassID)] = files
        }

        let art = CreativeFolder.load(from: page.appending(path: CreativeFolder.folderName))
        if art.isEmpty == false {
            content.creative[folder] = art
        }

        for locale in DirectoryListing.directories(in: page)
            where CustomPageFolders.reservedNames.contains(locale.lastPathComponent) == false {
            for device in DirectoryListing.directories(in: locale) {
                let slot = CustomPageSlot(
                    page: folder, locale: locale.lastPathComponent, deviceClassID: device.lastPathComponent
                )
                content.screenshots[slot] = DirectoryListing.files(in: device).map(ImageInspector.inspect)
            }
        }
    }

    private static func read<Value: Decodable>(_ type: Value.Type, from url: URL) throws -> Value {
        try ProjectJSON.decoder().decode(type, from: Data(contentsOf: url))
    }
}
