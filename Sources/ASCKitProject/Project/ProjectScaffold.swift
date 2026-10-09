import Foundation

/// Makes a new project on disk: the configuration, the version folder, and a
/// first app information file, so a new listing starts from something rather than nothing.
public enum ProjectScaffold {
    /// The folder a new project goes in, beside the `.xcodeproj`.
    ///
    /// Hidden, because it sits in the root of a repository next to the Xcode
    /// project and belongs to a tool rather than to the app being built.
    ///
    /// Only used when making one. Opening takes a folder as it is found, so a
    /// project made before this keeps the name it has.
    public static let folderName = ".asckit"

    /// Folder names a project may already be in, newest first.
    ///
    /// `asckit` and `appstore` are what earlier versions wrote. Nothing renames
    /// them: a folder that works is left alone.
    public static let knownFolderNames = [folderName, "asckit", "appstore"]

    /// Where a screenshot waits before ASCKit puts it in a set.
    public static let inboxName = "inbox"

    public static let readmeName = "README.md"

    /// What goes in `inbox/.gitignore`.
    ///
    /// Git reads a `.gitignore` in every folder it walks, and the rules add to
    /// the ones above rather than replacing them. So this keeps the inbox out
    /// of the repository without a line in the repository's own `.gitignore`,
    /// and a project that moves to another repository takes the rule with it.
    ///
    /// The file names itself, or the rule above would hide it and the folder
    /// would not survive a clone. `.gitkeep` is named for a project made before
    /// this file existed, which has one and should keep it.
    static let inboxIgnoreText = """
    # Screenshots wait here until ASCKit files them under versions/. What is in
    # this folder is on its way somewhere else, so git has no use for it.
    *
    !.gitignore
    !.gitkeep
    """

    /// Writes the project and returns the folder holding its configuration.
    ///
    /// The folder it returns is inside the one it was given. A sandboxed caller
    /// has permission for the folder somebody picked, and that permission
    /// reaches the children only while it is open, so anything the caller wants
    /// to do with the returned folder has to happen before it closes.
    ///
    /// Refuses rather than writes into a folder that already has a project in
    /// it, because overwriting a configuration would take the key ids with it.
    @discardableResult
    public static func create(
        in parentURL: URL,
        config: ProjectConfig,
        version: String
    ) throws -> URL {
        let folder = parentURL.appending(path: folderName)

        guard FileManager.default.fileExists(
            atPath: folder.appending(path: Project.defaultConfigName).path
        ) == false else {
            throw ScaffoldError.alreadyAProject(at: folder)
        }

        try write(into: folder, config: config, version: version)
        return folder
    }

    /// Writes the project straight into a folder, with no `.asckit` inside it.
    ///
    /// This is for a project kept outside the repository. Its cache lives in a
    /// cache root, so no `cache/` is made here.
    ///
    /// Refuses a folder that already has a configuration, for the same reason
    /// `create(in:)` does.
    @discardableResult
    public static func create(at folder: URL, config: ProjectConfig, version: String) throws -> URL {
        guard FileManager.default.fileExists(
            atPath: folder.appending(path: Project.defaultConfigName).path
        ) == false else {
            throw ScaffoldError.alreadyAProject(at: folder)
        }

        try write(into: folder, config: config, version: version, withCache: false)
        return folder
    }

    /// Writes a whole project into a folder, whatever the folder is called.
    ///
    /// Separate from `create` because rebuilding writes into the folder it was
    /// given rather than into a child of it. A sandboxed app that opened the
    /// project folder directly has permission for that folder and not for its
    /// parent, so a rebuild must never reach upwards.
    static func write(
        into folder: URL,
        config: ProjectConfig,
        version: String,
        withCache: Bool = true
    ) throws {
        let copyFolder = Project.informationFolder(
            in: folder.appending(path: config.versionsPath).appending(path: version)
        )
        try FileManager.default.createDirectory(at: copyFolder, withIntermediateDirectories: true)

        try ProjectJSON.write(config, to: folder.appending(path: Project.defaultConfigName))

        // A draft rather than approved, because nothing has been written yet
        // and an empty listing must not be publishable.
        let copy = AppInformation(locale: config.sourceLocale, status: .draft)
        try ProjectJSON.write(copy, to: copyFolder.appending(path: "\(config.sourceLocale).json"))

        try makeInbox(in: folder)
        if withCache {
            try makeCache(at: folder.appending(path: Project.cacheFolderName))
        }
        try writeReadme(in: folder)
    }

    /// What goes in `cache/.gitignore`.
    ///
    /// Everything here came from App Store Connect and can be read again, so it
    /// is nobody's work and it does not belong in the repository. A price
    /// ladder in particular is large and goes out of date.
    static let cacheIgnoreText = """
    # What ASCKit read from App Store Connect and kept, so a window opens
    # without asking again. All of it can be read again, so git has no use for
    # it.
    *
    !.gitignore
    """

    /// Makes the folder ASCKit keeps what it read from App Store Connect in.
    ///
    /// The folder needs a tracked file in it or it does not survive a clone,
    /// and the `.gitignore` is that file and the rule that empties the folder
    /// at the same time. That is what the inbox does, for the same reason. A
    /// cache outside the repository gets one too, which does no harm.
    static func makeCache(at cache: URL) throws {
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)

        let ignore = cache.appending(path: ".gitignore")
        guard FileManager.default.fileExists(atPath: ignore.path) == false else { return }
        try Data(cacheIgnoreText.utf8).write(to: ignore)
    }

    /// Writes the README that says what every file in the folder is.
    ///
    /// Only ever called while making a project. Nothing writes over an existing
    /// one, because once the folder is somebody's, what is in it is theirs.
    static func writeReadme(in folder: URL) throws {
        let url = folder.appending(path: readmeName)
        guard FileManager.default.fileExists(atPath: url.path) == false else { return }
        try Data(ProjectReadme.text.utf8).write(to: url)
    }

    /// Where a screenshot waits before it goes into a set.
    ///
    /// The app runs in the sandbox and can read only the folder somebody gave
    /// it, so an image on the Desktop is out of reach and an image here is not.
    ///
    /// Git does not track an empty folder, so the folder needs a tracked file
    /// in it or it does not survive a clone. The `.gitignore` is that file and
    /// the rule that empties the folder, both at once.
    static func makeInbox(in folder: URL) throws {
        let inbox = folder.appending(path: inboxName)
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)

        let ignore = inbox.appending(path: ".gitignore")
        guard FileManager.default.fileExists(atPath: ignore.path) == false else { return }
        try Data(inboxIgnoreText.utf8).write(to: ignore)
    }
}

public enum ScaffoldError: Error, CustomLocalizedStringResourceConvertible {
    case alreadyAProject(at: URL)

    public var localizedStringResource: LocalizedStringResource {
        switch self {
        case let .alreadyAProject(folder):
            LocalizedStringResource("There is already a project at \(folder.path). Open it instead.", bundle: .here)
        }
    }
}

extension ScaffoldError: CustomStringConvertible {
    public var description: String { String(localized: localizedStringResource) }
}
