import ArgumentParser
import ASCKitProject
import Foundation

/// Putting the file names of a version back under the naming rule.
///
/// For a folder written before the rule existed. Adding or removing one image
/// names a whole set again, so this is for the sets nobody has touched since.
struct FixNames: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "fix-names",
        abstract: "Name every screenshot in a version the way ASCKit names them.",
        discussion: """
        Every screenshot is called \(ScreenshotNaming.example): the number, what the screenshot \
        shows, the device class, then the language. The folder decides the device class and the \
        language, so a file that says another one is put right here.

        The name matters beyond the folder. It goes to App Store Connect with the image, and the \
        next push looks for it there. A set uploaded under a name ASCKit would not write is a \
        set the next push reads as somebody else's work.

        With no flag it says what it would rename and writes nothing.
        """
    )

    @OptionGroup var options: ProjectOptions

    @Flag(name: .long, help: "Rename the files.")
    var write = false

    func run() throws {
        let project = try options.loadProject()
        let result = try Checker.check(project: project, version: options.appVersion)

        guard let version = result.versionString else {
            print("This project has no versions yet, so there is nothing to name.")
            throw ExitCode.failure
        }

        guard write else {
            try report(version: version, in: project)
            return
        }

        let moved = try ContentWriter.repairNames(version: version, in: project)
        guard moved.isEmpty == false else {
            print("Every screenshot in \(version) is already named the way ASCKit names them.")
            return
        }

        for move in moved {
            print("\(move.from) -> \(move.to)")
        }
        print("")
        print("Renamed \(moved.count) \(moved.count == 1 ? "file" : "files").")
    }

    /// What a rename would do, read off the check rather than off the files, so
    /// what this prints is what the app shows.
    private func report(version: String, in project: Project) throws {
        let problems = try Checker.check(project: project, version: version).problems
            .filter { $0.kind == .screenshotsNamedWrong }

        guard problems.isEmpty == false else {
            print("Every screenshot in \(version) is already named the way ASCKit names them.")
            return
        }

        for problem in problems {
            print(String(localized: problem.message))
        }
        print("")
        print("Run asckit fix-names --write to rename them.")
    }
}
