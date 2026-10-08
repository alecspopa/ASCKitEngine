import ArgumentParser
import ASCKitAPI
import ASCKitProject
import Foundation

/// Writing the names and descriptions of the in-app purchases.
struct PushProducts: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "products",
        abstract: "Write the names and descriptions of the in-app purchases.",
        discussion: """
        Touches no prices. Reads App Store Connect, shows exactly what would change, and asks \
        before writing anything.

        A name and a description go out together, because App Store Connect wants both when it \
        makes a language and there is no reason to make two calls.

        One language failing does not stop the rest, and one product failing does not stop the \
        others. Running this again writes only what is still different, so the ones that failed \
        are the ones that get another go.

        The words of a product live in a version. When App Review is done with that version, \
        this makes a new draft that copies it, the way App Store Connect does when you save \
        there. The draft goes to review only when you send it. A product whose words are in \
        review now is named in the plan and left alone.

        --dry-run builds every request and sends none of them, and prints the exact body App \
        Store Connect would read.
        """
    )

    @OptionGroup var options: ProjectOptions

    @Flag(name: .long, help: "Print the exact request bodies and send nothing.")
    var dryRun = false

    @Flag(name: .long, help: "Do not ask. Use only for a plan you have already read.")
    var yes = false

    func run() async throws {
        let project = try options.loadProject()

        let checked = try Checker.check(project: project, version: options.appVersion)
        try stopOnProductErrors(checked, project: project)

        let client = try ASCClient(key: PrivateKeyStore.apiKey(for: project.config))
        let session = PushSession(project: project, client: client)
        let reading = try await session.read(
            version: options.appVersion,
            includeScreenshots: false
        )

        guard let plan = reading.changes else {
            print("Nothing was read from App Store Connect.")
            throw ExitCode.failure
        }

        for line in ChangePlanFormatter.productWordLines(for: plan) {
            print(line)
        }

        guard plan.hasProductTextChanges else {
            print("No in-app purchase words to change.")
            return
        }

        if dryRun {
            try await showWhatWouldGo(session: session, reading: reading)
            return
        }

        guard yes || confirm("Write these words to App Store Connect?") else {
            print("Nothing written.")
            throw ExitCode.failure
        }

        let outcome = try await session.pushProductText(reading) { print("  writing \($0)…") }
        report(outcome.result)
        reportReceipt(outcome, project: project)

        if outcome.result.isCompleteSuccess == false { throw ExitCode.failure }
    }

    // MARK: - Looking before writing

    /// How many bodies to print in full.
    ///
    /// One request per product per language, and after the first few they
    /// differ only in the words. Printing every one buries the thing somebody
    /// opened this to look at.
    private static let bodiesShown = 3

    private func showWhatWouldGo(
        session: PushSession,
        reading: PushSession.Reading
    ) async throws {
        let bodies = try await session.pushProductText(reading, dryRun: true).result.wouldSend
        print("")
        print("\(bodies.count) request\(bodies.count == 1 ? "" : "s") would go. Nothing was sent.")

        for body in bodies.prefix(Self.bodiesShown) {
            print("")
            print(body)
        }

        let hidden = bodies.count - Self.bodiesShown
        if hidden > 0 {
            print("")
            print("...and \(hidden) more like it, one per language, differing only in the "
                + "words and the row they name.")
        }
    }

    /// Anything wrong with a price does not stop the words going out. They are
    /// different halves, and a price is written by a different command.
    private func stopOnProductErrors(_ checked: CheckResult, project: Project) throws {
        let relevant = checked.errors.filter { $0.area == .products }
        guard relevant.isEmpty else {
            for problem in relevant {
                print(ProblemFormatter.line(for: problem, rootURL: project.rootURL))
            }
            print("")
            print("Fix these first. Nothing was written.")
            throw ExitCode.failure
        }
    }

    private func report(_ result: ProductPusher.TextResult) {
        print("")
        if result.written.isEmpty == false {
            print("Written: \(result.written.joined(separator: ", "))")
        }
        guard result.failed.isEmpty == false else { return }

        print("Failed:")
        for failure in result.failed {
            print("  \(failure.productID) \(failure.what): \(failure.reason)")
        }
        print("")
        print("Run asckit push products again to try these. It reads App Store Connect first, "
            + "so only what is still different goes out.")
    }
}
