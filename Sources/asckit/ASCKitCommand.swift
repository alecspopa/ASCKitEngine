import ArgumentParser
import ASCKitProject
import Foundation

@main
struct ASCKitCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "asckit",
        abstract: "Check and publish App Store Connect listings from files on disk.",
        version: "0.3.1",
        subcommands: [
            Init.self, Check.self, Silence.self, Ignore.self, CopyScreenshots.self, FixNames.self, Pull.self,
            Diff.self, InboxCommand.self, Price.self, Push.self, Experiments.self,
            PushExperimentImages.self, CustomPages.self, PushCustomPages.self, Library.self
        ],
        defaultSubcommand: Check.self
    )
}

/// Shared by every subcommand, so a folder means the same thing everywhere.
///
/// The folder holding the Xcode project, which is the folder `init` was run in
/// and the folder the app opens. The listing is in the folder that
/// `~/Documents/ASCKit/locations.json` names for it, or in `.asckit` inside it
/// for an older project.
struct ProjectOptions: ParsableArguments {
    @Argument(help: ArgumentHelp(
        "The folder holding the Xcode project. Defaults to the current one.",
        valueName: "folder"
    ))
    var folder: String = "."

    @Option(
        name: .long,
        help: ArgumentHelp("Which version to work on. Defaults to the newest.", valueName: "version")
    )
    var appVersion: String?

    @Option(
        name: .long,
        help: ArgumentHelp(
            "The project data folder. Defaults to the one in ~/Documents/ASCKit/locations.json.",
            valueName: "path"
        )
    )
    var data: String?

    var folderURL: URL {
        URL(fileURLWithPath: folder, relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
            .standardizedFileURL
    }

    /// Where ASCKit keeps what it read from App Store Connect, one folder per
    /// app.
    static var cacheRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appending(path: "Library").appending(path: "Caches").appending(path: "asckit")
    }

    /// The project for the folder. Refuses a folder with no Xcode project, the
    /// same as the app does.
    func loadProject() throws -> Project {
        if let data {
            return try Project.open(
                repo: folderURL,
                data: URL(fileURLWithPath: data, relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
                    .standardizedFileURL,
                cacheRoot: Self.cacheRoot
            )
        }

        let home = FileManager.default.homeDirectoryForCurrentUser
        var locations: ProjectLocations
        do {
            locations = try ProjectLocations.load(root: ProjectLocations.defaultRoot(home: home))
        } catch {
            // A broken registry says nothing about a project kept in the
            // repository, so that one still opens.
            guard Project.alreadyAProject(in: folderURL) else { throw error }
            return try Project.open(at: folderURL)
        }

        guard
            let resolution = locations.resolve(repo: folderURL),
            resolution.source != .inRepo
        else {
            return try Project.open(at: folderURL)
        }

        let project = try Project.open(repo: folderURL, data: resolution.dataURL, cacheRoot: Self.cacheRoot)

        // Written down so the next run finds it by repository, and a project
        // whose bundle identifier changed is still found.
        if resolution.source != .registeredByRepo {
            locations.register(bundleID: project.config.bundleID, data: resolution.dataURL, repo: folderURL)
            try? locations.save()
        }
        return project
    }
}
