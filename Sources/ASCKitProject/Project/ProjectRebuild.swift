import Foundation

/// Scaffolding over a project that is already there.
///
/// The project folder goes and a fresh one takes its place. That is every
/// language, every screenshot and every push record, so nothing here happens
/// without a caller first asking what would be lost: `plan(at:)` answers that,
/// and `rebuild` will only take a plan.
///
/// Nothing outside the project folder is ever touched. A caller names the
/// folder a person picked, which is the repository holding the `.xcodeproj`,
/// and `plan(at:)` resolves the `.asckit` folder inside it. The repository and
/// everything else in it are left exactly as they are.
public enum ProjectRebuild {
    /// What a rebuild would take away.
    public struct Plan: Sendable {
        /// The project folder, `.asckit` in a repository. Everything a rebuild
        /// removes is this folder or something inside it.
        public let folderURL: URL

        /// The things directly inside the project folder, which is what a
        /// person is shown.
        public let entries: [URL]

        /// What actually moves to the Trash: the project folder itself when the
        /// caller named the repository around it, and otherwise everything
        /// inside it.
        ///
        /// Every caller names the repository, so the folder itself is what
        /// moves. Trashing a folder needs permission for the folder holding it,
        /// which a caller naming the project folder cannot be assumed to have,
        /// so that one empties the folder instead of removing it.
        public let trash: [URL]

        /// Read out of the folder so a person is told in the words they think
        /// in, rather than being shown a list of paths.
        public let versions: [String]
        public let languages: [String]
        public let screenshotCount: Int
        public let hasHistory: Bool

        /// The configuration goes too, and with it the name of the key. The
        /// key stays in the key folder, so putting the same id back reaches it
        /// again.
        public let keyID: String?

        /// The configuration to start the new project from, when the old one
        /// could be read. Nil when the folder holds no readable project.
        public let currentConfig: ProjectConfig?

        public var isEmpty: Bool { entries.isEmpty }
    }

    /// Looks at a folder and says what a rebuild would remove. Writes nothing.
    ///
    /// Takes either the project folder or the repository holding it, and
    /// answers about the project folder in both cases.
    public static func plan(at folderURL: URL) -> Plan {
        let projectURL = projectFolder(for: folderURL)

        let entries = ((try? FileManager.default.contentsOfDirectory(
            at: projectURL,
            includingPropertiesForKeys: nil,
            options: []
        )) ?? []).sorted { $0.lastPathComponent < $1.lastPathComponent }

        let project = try? Project.load(at: projectURL)
        let versions = (try? project?.versionNames()) ?? []

        // Counted by walking the folders rather than by loading the project.
        // Loading opens every screenshot to measure it, and none of those
        // measurements say anything about what is about to be lost.
        var languages: Set<String> = []
        var screenshotCount = 0

        for version in versions {
            guard let project else { break }

            let informationFolder = project.informationURL(version: version)
            languages.formUnion(
                names(in: informationFolder)
                    .filter { $0.hasSuffix(".json") }
                    .map { String($0.dropLast(".json".count)) }
            )

            screenshotCount += fileCount(under: project.screenshotsURL(version: version))
        }

        return Plan(
            folderURL: projectURL,
            entries: entries,
            trash: whatMoves(projectURL: projectURL, given: folderURL, entries: entries),
            versions: versions,
            languages: languages.sorted(),
            screenshotCount: screenshotCount,
            hasHistory: project.map { FileManager.default.fileExists(atPath: $0.historyURL.path) } ?? false,
            keyID: project?.config.keyID,
            currentConfig: project?.config
        )
    }

    /// The folder the project is in, given either that folder or the
    /// repository holding it.
    ///
    /// A repository with no project in it resolves to the `.asckit` that is not
    /// there yet, so a rebuild writes a project beside the Xcode project rather
    /// than over it.
    static func projectFolder(for folderURL: URL) -> URL {
        // A folder with an Xcode project in it is the repository, and a
        // repository is never the project folder. This holds even when a
        // configuration file is sitting in it, which is how a project made by
        // hand can look. Reading that folder as the project folder would put
        // the source somebody is shipping in the Trash.
        guard XcodeProject.find(in: folderURL) == nil else {
            return Project.projectFolder(under: folderURL)
        }

        let here = folderURL.appending(path: Project.defaultConfigName)
        if FileManager.default.fileExists(atPath: here.path) { return folderURL }

        // A folder already called what a project folder is called is one, even
        // with nothing in it. Nothing in ASCKit names one, and reading it as a
        // repository would put a project inside a project.
        if ProjectScaffold.knownFolderNames.contains(folderURL.lastPathComponent) {
            return folderURL
        }

        return Project.projectFolder(under: folderURL)
    }

    /// The folder itself when it sits inside the folder the caller named, and
    /// what is inside it when the caller named the project folder itself.
    private static func whatMoves(projectURL: URL, given: URL, entries: [URL]) -> [URL] {
        let isInside = projectURL.standardizedFileURL.path != given.standardizedFileURL.path
        guard isInside, FileManager.default.fileExists(atPath: projectURL.path) else {
            return entries
        }
        return [projectURL]
    }

    private static func names(in folder: URL) -> [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
    }

    /// Every file under a folder, at any depth, ignoring the hidden ones the
    /// Finder leaves behind.
    private static func fileCount(under folder: URL) -> Int {
        guard let walker = FileManager.default.enumerator(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        return walker.reduce(0) { count, entry in
            guard
                let url = entry as? URL,
                (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true
            else {
                return count
            }
            return count + 1
        }
    }

    /// Moves what the plan named to the Trash, then scaffolds again.
    ///
    /// The Trash rather than a delete. This throws away work nobody can get
    /// back from App Store Connect, screenshots most of all, and a person who
    /// meant a different folder deserves to be able to undo it.
    ///
    /// Takes a plan rather than a folder, so nothing can rebuild without having
    /// asked what that would cost, and so the only paths it touches are the
    /// ones a person was shown.
    ///
    /// Returns where the old files went, so a caller can say so and point at
    /// them rather than claiming they are gone.
    @discardableResult
    public static func rebuild(
        _ plan: Plan,
        config: ProjectConfig,
        version: String
    ) throws -> [URL] {
        // Everything goes before anything is written, so a half-trashed folder
        // never has a fresh configuration sitting in it claiming to describe
        // what is left.
        var trashed: [URL] = []
        for entry in plan.trash {
            var landed: NSURL?
            try FileManager.default.trashItem(at: entry, resultingItemURL: &landed)
            if let landed = landed as URL? { trashed.append(landed) }
        }

        // Into the project folder, never into the repository around it. The
        // folder keeps its name, so a project living in one called `appstore`
        // still does.
        try ProjectScaffold.write(into: plan.folderURL, config: config, version: version)
        return trashed
    }
}
