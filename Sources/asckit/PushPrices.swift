import ArgumentParser
import ASCKitAPI
import ASCKitProject
import Foundation

/// Writing what the in-app purchases cost.
struct PushPrices: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "prices",
        abstract: "Write what the in-app purchases cost, country by country.",
        discussion: """
        This moves real money, so it asks more than the other push commands do.

        Read the whole table before you run it. asckit diff --prices shows every country. Here \
        the plan shows the twelve biggest moves.

        --dry-run builds every request and sends none of them, and prints the exact body App \
        Store Connect would get. That is the same body a real run sends, because the same code \
        makes both.

        A plan where any country pays more needs --yes-raise-prices as well as --yes. One word \
        is not enough for a rise.

        Every country goes in one request. A one-time purchase has a price schedule and a \
        subscription takes a compound update, and both carry every country at once, so nothing \
        is ever half applied.

        --one-country-at-a-time writes a subscription's countries one request each instead. \
        Slower, and the way to find out which country App Store Connect objected to when the \
        one request comes back refused without saying.

        One country failing does not stop the rest. Running this again reads the prices back \
        first, so only the countries that are still wrong go out, which is how the ones that \
        failed get another go.
        """
    )

    @OptionGroup var options: ProjectOptions

    @Flag(name: .long, help: "Print the exact request bodies and send nothing.")
    var dryRun = false

    @Flag(name: .long, help: "Do not ask. Use only for a table you have already read.")
    var yes = false

    @Flag(
        name: .long,
        help: "Agree to the countries that would pay more. Needed on top of --yes."
    )
    var yesRaisePrices = false

    @Flag(
        name: .long,
        help: "Write a subscription's countries one at a time, to find the one that is refused."
    )
    var oneCountryAtATime = false

    func run() async throws {
        let project = try options.loadProject()

        let checked = try Checker.check(project: project, version: options.appVersion)
        try stopOnPricingErrors(checked, project: project)

        let session = try makeSession(for: project)

        print("Reading every price the store will sell these at. This takes a moment.")
        let reading = try await session.read(
            version: options.appVersion,
            includeScreenshots: false,
            // Always App Store Connect. This writes money, and the price it
            // writes has to be worked out from what the store holds now.
            prices: .fresh
        )

        guard let plan = reading.changes else {
            print("Nothing was read from App Store Connect.")
            throw ExitCode.failure
        }

        for line in ChangePlanFormatter.priceLines(for: plan) {
            print(line)
        }
        for problem in reading.priceProblems {
            print(ProblemFormatter.line(for: problem, rootURL: project.rootURL))
        }

        guard plan.hasPriceChanges else {
            print("No prices to change.")
            return
        }

        if dryRun {
            try await showWhatWouldGo(session: session, reading: reading)
            return
        }

        try askAboutRises(plan)
        guard confirmed(yes: yes, "Write these prices to App Store Connect?") else {
            throw ExitCode.failure
        }

        let outcome = try await session.pushPrices(
            reading, oneCountryAtATime: oneCountryAtATime
        ) { print("  writing \($0)…") }
        report(outcome.result, plan: plan)
        reportReceipt(outcome, project: project)

        if outcome.result.isCompleteSuccess == false { throw ExitCode.failure }
    }

    // MARK: - Looking before writing

    /// How many bodies to print in full.
    ///
    /// A subscription is one request per country, and after the first couple
    /// they differ only in two ids. Printing a hundred and seventy seven of
    /// them buries the thing somebody opened this to look at.
    private static let bodiesShown = 2

    private func showWhatWouldGo(
        session: PushSession,
        reading: PushSession.Reading
    ) async throws {
        let bodies = try await session.pushPrices(
            reading, dryRun: true, oneCountryAtATime: oneCountryAtATime
        ).result.wouldSend
        print("")
        print("\(countedNoun(bodies.count, "request")) would go. Nothing was sent.")

        for body in bodies.prefix(Self.bodiesShown) {
            print("")
            print(body)
        }

        let hidden = bodies.count - Self.bodiesShown
        if hidden > 0 {
            print("")
            print("...and \(hidden) more like it, one per country, differing only in the "
                + "country and its price point.")
            print("Pass no --one-country-at-a-time to send them as one request instead.")
        }
    }

    /// A rise is the change that cannot be taken back, so one word is not
    /// enough for it.
    private func askAboutRises(_ plan: ChangePlan) throws {
        let rises = plan.priceRises
        guard rises.isEmpty == false else { return }

        print("")
        print("These countries would pay more:")
        for row in rises {
            let was = row.oldAmount?.formatted(currency: row.shownCurrency) ?? "none"
            print("  \(row.territory)  \(was) -> \(row.newAmount.formatted(currency: row.shownCurrency))")
        }

        let moving = plan.pricePlans.filter { $0.preserveCurrentPrice == false }
        if moving.isEmpty == false {
            print("")
            for change in moving {
                print("\(change.productID) moves people who already subscribe onto the new "
                    + "price. Apple emails them,")
                print("they have to agree, and the ones who do not answer are cancelled at "
                    + "renewal.")
            }
        }

        guard yesRaisePrices else {
            print("")
            print("Pass --yes-raise-prices as well to agree to these. Nothing written.")
            throw ExitCode.failure
        }
    }

    /// App Store Connect puts a cut and a rise in two different places, and
    /// somebody who has just lowered three hundred countries and raised two
    /// finds a page listing two. Without this they read that as a failure.
    private func sayWhereToLookForThem(_ plan: ChangePlan) {
        let falls = plan.pricePlans.reduce(0) { $0 + $1.falls.count }
        let rises = plan.priceRises.count

        if falls > 0 {
            print("  \(falls) went down. A cut takes effect at once, so look for those in the")
            print("  subscription's own price list.")
        }
        if rises > 0 {
            print("  \(rises) went up. A rise becomes a scheduled price change dated today, "
                + "and that")
            print("  page holds nothing else. People who already subscribe stay on the old "
                + "price,")
            print("  which App Store Connect shows beside the new one.")
        }
    }

    /// Anything wrong with a product's words does not stop a price going out.
    private func stopOnPricingErrors(_ checked: CheckResult, project: Project) throws {
        let relevant = checked.errors.filter { $0.area == .pricing || $0.area == .configuration }
        try stopOnErrors(relevant, project: project)
    }

    private func report(_ result: ProductPusher.PriceResult, plan: ChangePlan) {
        print("")
        if result.written.isEmpty == false {
            print("Written: \(result.written.count) prices.")
            sayWhereToLookForThem(plan)
        }
        guard result.failed.isEmpty == false else { return }

        print("Failed:")
        for failure in result.failed {
            let what = failure.what.isEmpty ? "" : " \(failure.what)"
            print("  \(failure.productID)\(what): \(failure.reason)")
        }
        print("")
        print("Run asckit push prices again to try these. It reads the prices back first, so "
            + "only the countries")
        print("that are still wrong go out.")
    }
}
