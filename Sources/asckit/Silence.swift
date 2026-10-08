import ArgumentParser
import ASCKitAPI
import ASCKitProject
import Foundation

/// Reads, adds to and clears the warnings silenced in a version. That
/// includes the in-app purchase warnings, which every version shares.
///
/// All of it goes through `WarningSilence` in the package, which is what the
/// app writes through as well, so a warning silenced in the terminal is
/// silenced in the window.
struct Silence: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "silence",
        abstract: "Read the warnings silenced in a version, silence more, or bring them back.",
        discussion: """
        With no flag it reads what is silenced now and changes no silence.

        A silence hides a warning about the listing in one version. It goes in \
        \(WarningSilence.fileName) beside the version. That file goes into git with the listing \
        it is about. The next version shows the warning again.

        A silence hides a warning about an in-app purchase in every version. It goes in \
        \(WarningSilence.fileName) in the products folder. A check of every version reads that \
        file.

        The list numbers the version silences first, then the product silences. --show takes any \
        number in the list. --clear empties both files.

        Errors are never silenced. An error is what App Store Connect refuses, and hiding one \
        would only move the refusal later.
        """
    )

    @OptionGroup var options: ProjectOptions

    @Flag(name: .long, help: "Silence every warning this version has now.")
    var all = false

    @Flag(name: .long, help: "Bring every warning in the list back, the in-app purchase ones too.")
    var clear = false

    @Option(
        name: .long,
        help: ArgumentHelp(
            "Bring one silenced warning back, by the number the list gives it.",
            valueName: "number"
        )
    )
    var show: Int?

    func run() throws {
        let project = try options.loadProject()
        let result = try Checker.check(project: project, version: options.appVersion)

        guard let version = result.versionString else {
            print("This project has no versions yet, so there is nothing to silence.")
            throw ExitCode.failure
        }

        let asked = [all, clear, show != nil].filter(\.self)
        guard asked.count <= 1 else {
            print("Pass one of --all, --clear and --show.")
            throw ExitCode.failure
        }

        if all {
            try silenceEverything(result, version: version, project: project)
        } else if clear {
            try showEverything(version: version, project: project)
        } else if let show {
            try showOne(numbered: show, version: version, project: project)
        } else {
            list(result, version: version, project: project)
        }
    }

    // MARK: - Reading

    /// The numbers come from the files, in the order `WarningSilence.readAll`
    /// gives. So the number beside a line is the one `--show` takes.
    private func list(_ result: CheckResult, version: String, project: Project) {
        let files = WarningSilence.readByFile(version: version, in: project)
        guard files.isEmpty == false else {
            print("Nothing is silenced in \(version).")
            return
        }

        var number = 0
        for file in files {
            print(heading(for: file.location))
            for warning in file.warnings {
                number += 1
                // A warning somebody silenced and then fixed leaves its silence
                // behind, and a file of decisions about nothing is worth clearing.
                let gone = result.staleSilences.contains(warning) ? "(gone) " : ""
                print("  \(number)  \(gone)\(warning.message)")
            }
            print("")
        }

        print("Bring one back with asckit silence --show <number>, or all of them with --clear.")
    }

    /// The product silences get their own heading, because they hide the
    /// warning in the next version too.
    private func heading(for location: WarningSilence.Location) -> String {
        switch location {
        case let .version(version): "Silenced in \(version):"
        case .products: "Silenced in every version:"
        }
    }

    // MARK: - Writing

    private func silenceEverything(_ result: CheckResult, version: String, project: Project) throws {
        let warnings = result.problems.warnings
        guard warnings.isEmpty == false else {
            print("\(version) has no warnings to silence.")
            return
        }

        for file in try WarningSilence.silenceByFile(warnings, version: version, in: project) {
            print(file.silencedSentence(in: project).english)
        }
    }

    private func showOne(numbered number: Int, version: String, project: Project) throws {
        let silenced = WarningSilence.readAll(version: version, in: project)
        guard number >= 1, number <= silenced.count else {
            print(silenced.isEmpty
                ? "Nothing is silenced in \(version)."
                : "There is no \(number) in the list. Run asckit silence to read it.")
            throw ExitCode.failure
        }

        let warning = silenced[number - 1]
        try WarningSilence.show([warning], version: version, in: project)
        print("Shows again: \(warning.message)")
    }

    private func showEverything(version: String, project: Project) throws {
        let files = try WarningSilence.showAllByFile(version: version, in: project)
        guard files.isEmpty == false else {
            print("Nothing was silenced in \(version).")
            return
        }

        for file in files {
            print(file.shownSentence.english)
        }
    }
}
