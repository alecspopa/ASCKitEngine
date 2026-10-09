import ArgumentParser
import ASCKitProject
import Foundation

@main
struct ASCKitCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "asckit",
        abstract: "Check and publish App Store Connect listings from files on disk.",
        version: "0.1.13",
        subcommands: [
            Init.self, Check.self, Silence.self, Ignore.self, CopyScreenshots.self, FixNames.self, Pull.self,
            Diff.self, InboxCommand.self, Price.self, Push.self, Experiments.self,
            PushExperimentImages.self, Library.self
        ],
        defaultSubcommand: Check.self
    )
}

/// Shared by every subcommand, so a folder means the same thing everywhere.
///
/// The folder holding the Xcode project, which is the folder `init` was run in
/// and the folder the app opens. The listing is in `.asckit` inside it.
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

    var folderURL: URL {
        URL(fileURLWithPath: folder, relativeTo: URL(fileURLWithPath: FileManager.default.currentDirectoryPath))
            .standardizedFileURL
    }

    /// The project in the folder. Refuses a folder with no Xcode project, the
    /// same as the app does.
    func loadProject() throws -> Project {
        try Project.open(at: folderURL)
    }
}
