import Foundation

/// Where each app's project data is kept, when it is not in the repository.
///
/// One file, `locations.json`, in the root folder (`~/Documents/ASCKit` by
/// default). The app and the `asckit` tool both read it, so both find the same
/// folder for the same repository. The app is sandboxed and the tool is not,
/// so neither can work out the other's answer without a file they share.
///
/// Foundation only, and no state outside the value, so a caller can load one,
/// change it and save it without any other setup.
public struct ProjectLocations: Sendable, Equatable {
    public static let fileName = "locations.json"

    /// The folder holding `locations.json` and the data folders beside it.
    public let root: URL

    /// What the registry says about one app.
    public struct Entry: Codable, Sendable, Equatable {
        /// A folder in the root. Relative, so it holds on every Mac that
        /// syncs the root.
        public var folder: String?

        /// A folder anywhere, for a person who put the data somewhere else.
        public var path: String?

        /// Repositories known to build this app, as absolute paths.
        public var repos: [String]

        public init(folder: String? = nil, path: String? = nil, repos: [String] = []) {
            self.folder = folder
            self.path = path
            self.repos = repos
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            folder = try container.decodeIfPresent(String.self, forKey: .folder)
            path = try container.decodeIfPresent(String.self, forKey: .path)
            repos = try container.decodeIfPresent([String].self, forKey: .repos) ?? []
        }
    }

    /// The entries, by bundle identifier.
    public private(set) var entries: [String: Entry]

    /// How a folder was found, so a caller knows when to write the repository
    /// down.
    public struct Resolution: Sendable, Equatable {
        public enum Source: Sendable, Equatable {
            case registeredByRepo
            case registeredByBundleID
            case foundByScan
            case inRepo
        }

        public let dataURL: URL

        /// Nil when the folder was found without reading it, which is the case
        /// for a project kept in the repository.
        public let bundleID: String?

        public let source: Source
    }

    /// The file as it is written.
    private struct File: Codable {
        var version = 1
        var projects: [String: Entry]
    }

    public init(root: URL, entries: [String: Entry] = [:]) {
        self.root = root
        self.entries = entries
    }

    // MARK: - Reading and writing

    /// `Documents/ASCKit` under a home folder.
    ///
    /// The caller names the home. A sandboxed app has a home of its own and
    /// needs the real one, so nothing here guesses.
    public static func defaultRoot(home: URL) -> URL {
        home.appending(path: "Documents").appending(path: "ASCKit")
    }

    /// A missing file is an empty registry, because nobody has made a project
    /// outside a repository yet. A file that is there and cannot be read is an
    /// error, because writing over it would lose what it holds.
    public static func load(root: URL) throws -> ProjectLocations {
        let url = root.appending(path: fileName)
        guard FileManager.default.fileExists(atPath: url.path) else {
            return ProjectLocations(root: root)
        }

        do {
            let file = try ProjectJSON.decoder().decode(File.self, from: Data(contentsOf: url))
            return ProjectLocations(root: root, entries: file.projects)
        } catch {
            throw ProjectLocationsError.unreadable(url: url, underlying: error)
        }
    }

    public func save() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try ProjectJSON.write(
            File(projects: entries),
            to: root.appending(path: Self.fileName),
            atomic: true
        )
    }

    // MARK: - Looking up

    /// The data folder registered for an app.
    public func dataURL(for bundleID: String) -> URL? {
        guard let entry = entries[bundleID] else { return nil }
        if let folder = entry.folder {
            return root.appending(path: folder)
        }
        return entry.path.map { URL(fileURLWithPath: $0) }
    }

    /// Finds the data folder for a repository.
    ///
    /// Tried in order, and the first that answers wins:
    /// - the repository is written down in an entry
    /// - the Xcode project builds an app that has an entry
    /// - a folder in the root holds a configuration for an app the Xcode
    ///   project builds, which recovers a registry that was lost
    /// - the repository has a project folder of its own
    public func resolve(repo: URL) -> Resolution? {
        let repoPath = Self.path(of: repo)

        if let bundleID = entries.keys.sorted().first(where: { entries[$0]?.repos.contains(repoPath) == true }),
           let url = dataURL(for: bundleID) {
            return Resolution(dataURL: url, bundleID: bundleID, source: .registeredByRepo)
        }

        let appIDs = Self.bundleIDs(in: repo)

        let registered = appIDs.filter { dataURL(for: $0) != nil }
        if registered.count == 1, let url = dataURL(for: registered[0]) {
            return Resolution(dataURL: url, bundleID: registered[0], source: .registeredByBundleID)
        }

        if registered.isEmpty, let found = scan(for: appIDs) {
            return Resolution(dataURL: found.url, bundleID: found.bundleID, source: .foundByScan)
        }

        if Project.alreadyAProject(in: repo) {
            return Resolution(dataURL: Project.projectFolder(under: repo), bundleID: nil, source: .inRepo)
        }
        return nil
    }

    /// The bundle identifiers of the apps an Xcode project builds, with the
    /// ones it cannot resolve left out.
    private static func bundleIDs(in repo: URL) -> [String] {
        guard
            let url = XcodeProject.find(in: repo),
            let xcode = try? XcodeProject.read(at: url)
        else {
            return []
        }
        return xcode.apps.compactMap(\.bundleID)
    }

    /// The one folder in the root whose configuration is for one of these apps.
    private func scan(for bundleIDs: [String]) -> (url: URL, bundleID: String)? {
        guard bundleIDs.isEmpty == false else { return nil }

        let children = DirectoryListing.entries(in: root, keys: [])
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        let matches = children.compactMap { child -> (url: URL, bundleID: String)? in
            let configURL = child.appending(path: Project.defaultConfigName)
            guard
                let data = try? Data(contentsOf: configURL),
                let config = try? ProjectJSON.decoder().decode(ProjectConfig.self, from: data),
                bundleIDs.contains(config.bundleID)
            else {
                return nil
            }
            return (child, config.bundleID)
        }
        return matches.count == 1 ? matches[0] : nil
    }

    // MARK: - Changing

    /// Writes an app down, with the repository that builds it.
    ///
    /// A repository belongs to one app, so it leaves every other entry.
    public mutating func register(bundleID: String, data: URL, repo: URL) {
        let repoPath = Self.path(of: repo)

        for key in entries.keys {
            entries[key]?.repos.removeAll { $0 == repoPath }
        }

        var entry = Entry(repos: entries[bundleID]?.repos ?? [])
        let parent = Self.path(of: data.deletingLastPathComponent())
        if parent == Self.path(of: root) {
            entry.folder = data.lastPathComponent
        } else {
            entry.path = Self.path(of: data)
        }
        entry.repos.append(repoPath)
        entries[bundleID] = entry
    }

    /// The name for a new data folder.
    ///
    /// The app's name, so a person finds it in the Finder. The bundle
    /// identifier is added when another app has the name already.
    public func folderName(forDisplayName displayName: String, bundleID: String) -> String {
        let plain = displayName
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let name = plain.isEmpty ? bundleID : plain

        let takenByOther = entries.contains { key, entry in
            key != bundleID && entry.folder == name
        }
        let existsUnregistered = entries[bundleID]?.folder != name
            && FileManager.default.fileExists(atPath: root.appending(path: name).path)

        guard takenByOther || existsUnregistered else { return name }
        return "\(name) (\(bundleID))"
    }

    private static func path(of url: URL) -> String {
        url.standardizedFileURL.path
    }
}

public enum ProjectLocationsError: Error, CustomLocalizedStringResourceConvertible {
    case unreadable(url: URL, underlying: any Error)

    public var localizedStringResource: LocalizedStringResource {
        switch self {
        case let .unreadable(url, underlying):
            LocalizedStringResource("""
            Could not read \(url.path): \(String(describing: underlying)). Fix the file or move it \
            away, and ASCKit finds the projects again.
            """, bundle: .here)
        }
    }
}

extension ProjectLocationsError: CustomStringConvertible {
    public var description: String { String(localized: localizedStringResource) }
}
