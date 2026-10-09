import ArgumentParser
import ASCKitAPI
import ASCKitProject
import Foundation

struct Push: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "push",
        abstract: "Write the listing to App Store Connect.",
        subcommands: [PushText.self, PushImages.self, PushProducts.self, PushPrices.self],
        defaultSubcommand: PushText.self
    )
}

/// Asks before writing. Anything but yes is no, so a stray keypress or a
/// pipe with nothing on the other end leaves App Store Connect alone.
func confirm(_ question: String) -> Bool {
    print("")
    print("\(question) [y/N] ", terminator: "")
    guard let answer = readLine()?.trimmingCharacters(in: .whitespaces).lowercased() else {
        return false
    }
    return answer == "y" || answer == "yes"
}

/// Stops a push that has errors, naming each one. The caller picks the errors
/// that matter for its half of the listing.
func stopOnErrors(_ errors: [Problem], project: Project) throws {
    guard errors.isEmpty else {
        for problem in errors {
            print(ProblemFormatter.line(for: problem, rootURL: project.rootURL))
        }
        print("")
        print("Fix these first. Nothing was written.")
        throw ExitCode.failure
    }
}

/// True when the person said yes or passed `--yes`. Says so when it is no.
func confirmed(yes: Bool, _ question: String) -> Bool {
    if yes || confirm(question) { return true }
    print("Nothing written.")
    return false
}

/// Says where the record of a push went. The session files it, so nothing here
/// can push and forget to.
func reportReceipt(_ outcome: PushSession.Outcome<some Any>, project: Project) {
    if let url = outcome.receiptURL {
        print("Recorded in \(project.config.historyPath)/\(url.lastPathComponent)")
    }
    if let failure = outcome.receiptFailure {
        print("warning: could not write the receipt: \(failure)")
    }
}

struct PushText: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "text",
        abstract: "Write the listing text. Touches no screenshots.",
        discussion: """
        Checks the files, reads App Store Connect, shows exactly what would \
        change, and asks before writing anything.

        Only fields that differ are sent. A field the project does not set is \
        left alone rather than blanked, and a field that already matches is not \
        rewritten.

        One language failing does not stop the rest. A language added after \
        submission can be in a different state from the first one, so App Store \
        Connect can refuse one and accept another.
        """
    )

    @OptionGroup var options: ProjectOptions

    @Flag(name: .long, help: "Do not ask. Use only for a plan you have already read.")
    var yes = false

    @Flag(name: .long, help: "Write even the changes this version's state will refuse.")
    var ignoreBlocked = false

    func run() async throws {
        let project = try options.loadProject()

        let checked = try Checker.check(project: project, version: options.appVersion)
        try stopOnCopyErrors(checked, project: project)

        let session = try makeSession(for: project)
        let reading = try await session.read(version: options.appVersion, includeScreenshots: false)
        let listing = reading.listing
        let plan = try VersionCheck.plan(in: reading, project: project)

        print(versionHeader(listing, plan))
        print("")
        for line in ChangePlanFormatter.lines(for: plan) {
            print(line)
        }

        guard plan.textChanges.isEmpty == false else {
            print(ChangePlanFormatter.summary(plan))
            return
        }

        if plan.blocked(.appInformation).isEmpty == false, ignoreBlocked == false {
            throw PushError.blocked(plan.blocked(.appInformation))
        }

        print(ChangePlanFormatter.summary(plan))
        guard confirmed(yes: yes, "Write this to App Store Connect?") else {
            throw ExitCode.failure
        }

        let outcome = try await session.pushText(reading) { print("  writing \($0)…") }
        report(outcome.result)
        reportReceipt(outcome, project: project)

        if outcome.result.isCompleteSuccess == false { throw ExitCode.failure }
    }

    /// Screenshot problems do not stop a text push, because they are about a
    /// different half of the listing. Anything wrong with the words does.
    private func stopOnCopyErrors(_ checked: CheckResult, project: Project) throws {
        let relevant = checked.errors.filter { $0.area != .screenshots }
        try stopOnErrors(relevant, project: project)
    }

    private func report(_ result: TextPusher.Result) {
        print("")
        if result.written.isEmpty == false {
            print("Written: \(result.written.joined(separator: ", "))")
        }
        for refusal in result.refused {
            print("Refused, \(refusal.locale) \(refusal.field.rawValue):")
            print("  \(refusal.reason)")

            // Only true when something else in that language actually went.
            if result.written.contains(refusal.locale) {
                print("  Everything else in \(refusal.locale) went.")
            }
            print("  The field is still in the file, and a later version may take it.")
        }
        for failure in result.failed {
            print("Failed, \(failure.locale): \(failure.message)")
        }
        if result.isCompleteSuccess {
            print("Done. Read it back with asckit diff.")
        }
    }
}
