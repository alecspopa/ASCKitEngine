import ArgumentParser
import ASCKitProject
import Foundation

struct Check: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "check",
        abstract: "Check a project without touching App Store Connect.",
        discussion: """
        Reads the configuration, the app information files, the screenshots, the \
        images of the Product Page Optimization tests and the custom product pages, and reports \
        everything App Store Connect would refuse plus the things it would accept \
        but you would not want published.

        Exits non-zero when there is an error, so it works in a git hook. \
        Warnings on their own do not fail it unless --strict is given.
        """
    )

    @OptionGroup var options: ProjectOptions

    @Flag(name: .long, help: "Fail on warnings as well as errors.")
    var strict = false

    @Flag(name: .long, help: "Report errors only, and leave out the warnings.")
    var errorsOnly = false

    func run() throws {
        let project = try options.loadProject()
        let result = try Checker.check(project: project, version: options.appVersion)

        print(result.versionString.map { "\(project.config.bundleID), version \($0)" }
            ?? project.config.bundleID)

        // Tests and custom pages belong to no version, so their problems come
        // from their own folders.
        let validator = Validator(project: project)
        var experimentProblems = validator.validate(ExperimentContentStore.load(in: project))
            + validator.validate(
                CustomPageContentStore.load(in: project),
                keywords: CustomPageSnapshotStore.load(in: project)?.keywords
            )
        if errorsOnly { experimentProblems = experimentProblems.filter { $0.severity == .error } }

        let shown = (errorsOnly ? result.errors : result.problems) + experimentProblems
        for problem in shown {
            print(ProblemFormatter.line(for: problem, rootURL: project.rootURL))
        }

        if shown.isEmpty == false { print("") }
        print(ProblemFormatter.summary(
            shown,
            silenced: errorsOnly ? 0 : result.silenced.count
        ))
        if result.silenced.isEmpty == false, errorsOnly == false {
            print("Run asckit silence to read them.")
        }

        let all = result.problems + experimentProblems
        if all.contains(where: { $0.severity == .error })
            || (strict && all.contains(where: { $0.severity == .warning })) {
            throw ExitCode.failure
        }
    }
}
