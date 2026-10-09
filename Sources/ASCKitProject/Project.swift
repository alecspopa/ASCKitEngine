import Foundation

/// A project on disk: one configuration file and the content beside it.
public struct Project: Sendable {
    /// The configuration file itself, usually `asckit/asckit.json`.
    public let configURL: URL

    /// The directory holding it. Every other path is relative to this.
    public let rootURL: URL

    public let config: ProjectConfig

    public static let defaultConfigName = "asckit.json"

    /// The folder inside a version that holds the listing text, one file per
    /// language.
    ///
    /// Called `version-data` and not `app-information`, because App Store
    /// Connect has a tab called App Information and this folder holds more than
    /// that tab does. A name that reads as an App Store name, meaning something
    /// else, is worse than a name of our own.
    public static let informationFolderName = "version-data"

    /// Folder names the listing text may already be in, newest first.
    ///
    /// `app-information` is what earlier versions wrote. Nothing renames one: a
    /// folder that works is left alone, the same way a project folder called
    /// `appstore` keeps its name.
    public static let knownInformationFolderNames = [informationFolderName, "app-information"]

    public init(configURL: URL, config: ProjectConfig) {
        self.configURL = configURL
        rootURL = configURL.deletingLastPathComponent()
        self.config = config
    }

    /// Loads the project in a folder holding an Xcode project.
    ///
    /// This is how ASCKit opens a project, in the app and on the command line
    /// alike. A folder with no `.xcodeproj` is refused before anything in it is
    /// read.
    public static func open(at folderURL: URL) throws -> Project {
        try checkXcodeProject(in: folderURL)
        return try load(at: folderURL)
    }

    /// Throws when a folder holds no single Xcode project.
    ///
    /// ASCKit reads the app's name, its bundle identifier, the version it
    /// builds and the languages it ships out of the `.xcodeproj`. A folder with
    /// none says nothing about which app a listing belongs to.
    ///
    /// Reads nothing else, so a caller can refuse a folder before it opens a
    /// window on it or remembers it.
    public static func checkXcodeProject(in folderURL: URL) throws {
        guard XcodeProject.find(in: folderURL) == nil else { return }
        throw ProjectError.noXcodeProject(at: folderURL)
    }

    /// Accepts the configuration file, the folder holding it, or the folder
    /// holding that.
    ///
    /// The last one is how a project is opened: a person picks the folder with
    /// the `.xcodeproj` in it, and the listing is in `.asckit` beside it. The
    /// other two are how the project folder itself is read, once something has
    /// already found it.
    public static func load(at url: URL) throws -> Project {
        // `hasDirectoryPath` only looks for a trailing slash on the string, so
        // it says no to a real folder built with `appending(path:)`. Ask the
        // file system instead.
        var isDirectory: ObjCBool = false
        FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)

        let configURL = isDirectory.boolValue ? configuration(under: url) : url

        guard FileManager.default.fileExists(atPath: configURL.path) else {
            throw ProjectError.noConfigurationFile(at: configURL)
        }

        let data: Data
        do {
            data = try Data(contentsOf: configURL)
        } catch {
            throw ProjectError.unreadableFile(url: configURL, underlying: error)
        }

        do {
            return try Project(configURL: configURL, config: JSONDecoder().decode(ProjectConfig.self, from: data))
        } catch {
            throw ProjectError.unreadableConfiguration(url: configURL, underlying: error)
        }
    }

    /// The configuration a folder holds, either directly or in a project folder
    /// inside it.
    ///
    /// When there is none anywhere, the path a new project would be written to
    /// is returned, so the error names the place a person would have looked.
    static func configuration(under folderURL: URL) -> URL {
        let here = folderURL.appending(path: defaultConfigName)
        if FileManager.default.fileExists(atPath: here.path) { return here }

        for name in ProjectScaffold.knownFolderNames {
            let inside = folderURL.appending(path: name).appending(path: defaultConfigName)
            if FileManager.default.fileExists(atPath: inside.path) { return inside }
        }

        // A repository, so the missing file is the one inside it. Naming the
        // repository root would send a person to a path nothing writes.
        guard XcodeProject.find(in: folderURL) == nil else {
            return projectFolder(under: folderURL).appending(path: defaultConfigName)
        }
        return here
    }

    /// The folder a project would go in, for a folder with a `.xcodeproj`.
    ///
    /// The one already there when there is one, so nothing is scaffolded beside
    /// a project that exists under an older name.
    public static func projectFolder(under folderURL: URL) -> URL {
        for name in ProjectScaffold.knownFolderNames {
            let inside = folderURL.appending(path: name)
            if FileManager.default.fileExists(atPath: inside.appending(path: defaultConfigName).path) {
                return inside
            }
        }
        return folderURL.appending(path: ProjectScaffold.folderName)
    }

    /// Whether a folder already holds a listing, either in `.asckit` or in the
    /// folder an older project is in.
    ///
    /// Reads nothing but the file system, so a caller can tell a folder to open
    /// from a folder to scaffold before it does either.
    public static func alreadyAProject(in folderURL: URL) -> Bool {
        FileManager.default.fileExists(
            atPath: projectFolder(under: folderURL).appending(path: defaultConfigName).path
        )
    }

    /// Writes a changed configuration back over the one this project was loaded
    /// from.
    ///
    /// The project itself keeps the configuration it was loaded with, because a
    /// `Project` is what one read of the folder found. Whoever writes reads the
    /// folder again to see the change.
    public func write(_ config: ProjectConfig) throws {
        try ProjectJSON.write(config, to: configURL)
    }

    public var versionsURL: URL { rootURL.appending(path: config.versionsPath) }
    public var historyURL: URL { rootURL.appending(path: config.historyPath) }

    /// Where the in-app purchases live, one file per product.
    ///
    /// Beside the configuration file, not inside a version. A product hangs off
    /// the app: its price takes effect on the date the price says, and no
    /// release is involved. A copy in every version folder would let two
    /// folders disagree about the price of one product.
    public var productsURL: URL { rootURL.appending(path: config.productsPath) }

    public func productURL(productID: String) -> URL {
        productsURL.appending(path: "\(productID).json")
    }

    public var subscriptionGroupsURL: URL {
        productsURL.appending(path: ProductStore.groupsFolderName)
    }

    public func subscriptionGroupURL(name: String) -> URL {
        subscriptionGroupsURL.appending(path: "\(name).json")
    }

    /// This project's own price curves, for a shape none of the shipped ones
    /// have.
    public var priceCurvesURL: URL { rootURL.appending(path: "price-curves") }

    /// Things ASCKit read from App Store Connect and kept, so a window opens
    /// without asking again. Never in the repository.
    public var cacheURL: URL { rootURL.appending(path: "cache") }

    /// The version folders, newest-looking last. Sorted the way version numbers
    /// read rather than the way strings sort, so 1.10 comes after 1.9.
    public func versionNames() throws -> [String] {
        guard FileManager.default.fileExists(atPath: versionsURL.path) else { return [] }
        let entries = try FileManager.default.contentsOfDirectory(
            at: versionsURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        return entries
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false }
            .map(\.lastPathComponent)
            .sorted { $0.isNaturallyBefore($1) }
    }

    public func versionURL(_ version: String) -> URL {
        versionsURL.appending(path: version)
    }

    /// The folder holding this version's listing text.
    public func informationURL(version: String) -> URL {
        Self.informationFolder(in: versionURL(version))
    }

    /// The folder a version's listing text goes in, given the version folder.
    ///
    /// The one already there when there is one, so a project written before the
    /// rename keeps reading and writing the folder it has. Static, because the
    /// scaffold names a version folder before there is a project to load.
    public static func informationFolder(in versionURL: URL) -> URL {
        for name in knownInformationFolderNames {
            let inside = versionURL.appending(path: name)
            if FileManager.default.fileExists(atPath: inside.path) { return inside }
        }
        return versionURL.appending(path: informationFolderName)
    }

    public func informationURL(version: String, locale: String) -> URL {
        informationURL(version: version).appending(path: "\(locale).json")
    }

    public func screenshotsURL(version: String) -> URL {
        versionsURL.appending(path: version).appending(path: "screenshots")
    }

    public func screenshotsURL(version: String, locale: String, deviceClassID: String) -> URL {
        screenshotsURL(version: version).appending(path: locale).appending(path: deviceClassID)
    }
}

public enum ProjectError: Error, CustomLocalizedStringResourceConvertible {
    case noXcodeProject(at: URL)
    case noConfigurationFile(at: URL)
    case unreadableFile(url: URL, underlying: any Error)
    case unreadableConfiguration(url: URL, underlying: any Error)
    case noSuchVersion(String)

    public var localizedStringResource: LocalizedStringResource {
        switch self {
        case let .noXcodeProject(url):
            LocalizedStringResource("""
            There is no single .xcodeproj in \(url.lastPathComponent). ASCKit reads the app \
            out of the Xcode project, so use the folder that holds one.
            """, bundle: .here)
        case let .noConfigurationFile(url):
            LocalizedStringResource("""
            No configuration file at \(url.path). A project needs an \(Project.defaultConfigName).
            """, bundle: .here)
        case let .unreadableFile(url, underlying):
            LocalizedStringResource("Could not read \(url.path): \(underlying.localizedDescription)", bundle: .here)
        case let .unreadableConfiguration(url, underlying):
            LocalizedStringResource("""
            \(url.lastPathComponent) is not valid: \(String(describing: underlying))
            """, bundle: .here)
        case let .noSuchVersion(version):
            LocalizedStringResource("There is no folder for version \(version).", bundle: .here)
        }
    }
}

extension ProjectError: CustomStringConvertible {
    public var description: String { String(localized: localizedStringResource) }
}
