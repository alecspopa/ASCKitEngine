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

    @OptionGroup var confirmation: ConfirmOptions

    func run() async throws {
        let project = try options.loadProject()

        let checked = try Checker.check(project: project, version: options.appVersion)
        try stopOnProductErrors(checked, project: project)

        let session = try makeSession(for: project)
        let reading = try await session.read(
            version: options.appVersion,
            includeScreenshots: false
        )

        let plan = try plannedProducts(in: reading)

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

        try confirmation.require("Write these words to App Store Connect?")

        let outcome = try await session.pushProductText(reading) { print("  writing \($0)…") }
        report(outcome.result)
        try finish(outcome, project: project, succeeded: outcome.result.isCompleteSuccess)
    }

    // MARK: - Looking before writing

    /// After the first few, the bodies differ only in the words.
    private static let bodiesShown = 3

    private func showWhatWouldGo(
        session: PushSession,
        reading: PushSession.Reading
    ) async throws {
        let bodies = try await session.pushProductText(reading, dryRun: true).result.wouldSend
        printDryRun(
            bodies,
            shown: Self.bodiesShown,
            more: "one per language, differing only in the words and the row they name."
        )
    }

    /// Anything wrong with a price does not stop the words going out. They are
    /// different halves, and a price is written by a different command.
    private func stopOnProductErrors(_ checked: CheckResult, project: Project) throws {
        let relevant = checked.errors.filter { $0.area == .products }
        try stopOnErrors(relevant, project: project)
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
