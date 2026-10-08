import ASCKitAPI
import Foundation
import Testing
@testable import ASCKitProject

struct ProductFormatterTests {
    func row(
        _ territory: String,
        _ amount: Money,
        old: Money? = nil,
        direction: ChangePlan.PriceChange.Direction = .up,
        planType: ChangePlan.PriceChange.PlanType = .upfront,
        source: PriceResolver.Source = .curve(band: nil),
        roundedUpBy: Money = "0"
    ) -> ChangePlan.PriceChange.Row {
        ChangePlan.PriceChange.Row(
            territory: territory,
            planType: planType,
            currency: "USD",
            pricePointID: "\(territory)-\(amount)",
            oldAmount: old,
            newAmount: amount,
            direction: direction,
            source: source,
            roundedUpBy: roundedUpBy
        )
    }

    func plan(
        productText: [ChangePlan.ProductTextChange] = [],
        rows: [ChangePlan.PriceChange.Row] = [],
        kind: Product.Kind = .autoRenewableSubscription,
        preserveCurrentPrice: Bool? = true,
        skipped: [PriceResolver.Skipped] = []
    ) -> ChangePlan {
        ChangePlan(
            versionString: "1.0",
            versionState: nil,
            textChanges: [],
            missingLocales: [],
            screenshotPlans: [],
            productTextChanges: productText,
            pricePlans: rows.isEmpty ? [] : [ChangePlan.PriceChange(
                productID: "com.example.pro",
                kind: kind,
                baseTerritory: "USA",
                baseAmount: "4.99",
                curveID: "purchasing-power",
                replacesWholeSchedule: kind.priceWriteReplacesEveryTerritory,
                preserveCurrentPrice: kind.isAutoRenewable ? preserveCurrentPrice : nil,
                rows: rows,
                skipped: skipped
            )],
            newProducts: [],
            blocked: [],
            skipped: []
        )
    }

    func text(_ plan: ChangePlan, showingEveryPrice: Bool = false) -> String {
        ChangePlanFormatter.lines(for: plan, showingEveryPrice: showingEveryPrice)
            .joined(separator: "\n")
    }

    /// The same text with every line break gone, for a phrase that a wrap could
    /// fall in the middle of. A translation is a different length, so where the
    /// lines break is not something to write a test against.
    func flowed(_ plan: ChangePlan) -> String {
        ChangePlanFormatter.lines(for: plan)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .joined(separator: " ")
    }

    // MARK: - Words

    @Test func namesTheProductAndTheLanguageForEveryFieldItWouldWrite() {
        let written = text(plan(productText: [.init(
            productID: "com.example.pro", locale: "de-DE", field: .name,
            action: .change, oldValue: "Alt", newValue: "Neu"
        )]))
        #expect(written.contains("com.example.pro, de-DE"))
        #expect(written.contains("was:  Alt"))
        #expect(written.contains("now:  Neu"))
    }

    // MARK: - The two opposite rules

    /// Getting these the wrong way round reprices a hundred countries without
    /// saying so, so the plan says which one applies every time.
    @Test func warnsThatAOneTimePurchaseReplacesEveryCountryAtOnce() {
        let onePlan = plan(rows: [row("USA", "5.99", old: "4.99")], kind: .nonConsumable)
        #expect(flowed(onePlan).contains("replaces the whole price schedule"))
        #expect(flowed(onePlan).contains("goes back to"))
        #expect(text(onePlan).contains("keeps") == false)
    }

    /// A subscription goes in one request too, and ASCKit sends every country
    /// because Apple does not say whether that replaces the set or adds to it.
    @Test func saysThatASubscriptionSendsEveryCountryInOneRequest() {
        let onePlan = plan(rows: [row("USA", "5.99", old: "4.99")])
        #expect(flowed(onePlan).contains("Every country goes in one request"))
        #expect(flowed(onePlan).contains("no price schedule"))
        #expect(flowed(onePlan).contains("replaces the whole price schedule") == false)
    }

    @Test func saysThatExistingSubscribersKeepWhatTheyPay() {
        let written = text(plan(rows: [row("USA", "5.99", old: "4.99")]))
        #expect(written.contains("already subscribe keep what they pay"))
    }

    /// Moving people onto a new price is the thing that cannot be undone, so
    /// the plan spells out what Apple does to them.
    @Test func spellsOutWhatHappensWhenExistingSubscribersAreMoved() {
        let written = text(plan(
            rows: [row("USA", "5.99", old: "4.99")],
            preserveCurrentPrice: false
        ))
        #expect(written.contains("cancels the ones who do not answer"))
    }

    @Test func saysNothingAboutSubscribersForAOneTimePurchase() {
        let written = text(plan(rows: [row("USA", "5.99", old: "4.99")], kind: .nonConsumable))
        #expect(written.contains("already subscribe") == false)
    }

    // MARK: - Counts before rows

    /// Nobody reads a hundred and seventy seven lines, so the shape of the
    /// change comes first.
    @Test func countsTheCountriesBeforeListingAnyOfThem() {
        let written = ChangePlanFormatter.lines(for: plan(rows: [
            row("USA", "5.99", old: "4.99", direction: .up),
            row("IND", "199", old: "299", direction: .down),
            row("DEU", "5.99", old: "5.99", direction: .same)
        ]))
        let counts = written.firstIndex { $0.contains("countries:") } ?? 0
        // A row line, not the header, which names the base country too.
        let firstRow = written.firstIndex { $0.hasPrefix("      USA") } ?? 0
        #expect(counts < firstRow)
        #expect(written.contains { $0.contains("3 countries: 1 up, 1 down, 1 unchanged") })
    }

    /// A country the store charges nothing for yet is neither a rise nor a
    /// fall, so leaving it out of the counts loses it.
    @Test func countsANewCountrySeparately() {
        let written = ChangePlanFormatter.lines(for: plan(rows: [
            row("USA", "5.99", old: "4.99", direction: .up),
            row("AFG", "1.99", old: nil, direction: .new)
        ]))
        #expect(written.contains { $0.contains("2 countries: 1 up, 0 down, 1 new, 0 unchanged") })
    }

    @Test func printsOnlyTheFirstFewRowsAndSaysHowManyAreLeft() {
        let many = (1 ... 30).map { row("T\($0)", "1.99", old: "0.99") }
        let written = text(plan(rows: many))
        #expect(written.contains("...and 18 more."))
        #expect(written.contains("asckit diff --prices"))
    }

    @Test func printsEveryRowWhenAsked() {
        let many = (1 ... 30).map { row("T\($0)", "1.99", old: "0.99") }
        let written = text(plan(rows: many), showingEveryPrice: true)
        #expect(written.contains("asckit diff --prices") == false)
        #expect(written.contains("T30"))
    }

    /// A country that stays the same is still sent for a one-time purchase, but
    /// it is not what somebody is reading the plan for.
    @Test func leavesOutTheCountriesThatDoNotChange() {
        let written = text(plan(rows: [
            row("USA", "5.99", old: "4.99", direction: .up),
            row("DEU", "5.99", old: "5.99", direction: .same)
        ]))
        #expect(written.contains("USA"))
        #expect(written.contains("DEU") == false)
    }

    // MARK: - Saying what happened to a price

    @Test func saysWhenRoundingMovedAPrice() {
        let written = text(plan(rows: [
            row("USA", "5.99", old: "4.99", roundedUpBy: "0.40")
        ]))
        #expect(written.contains("rounded up"))
    }

    @Test func marksAPriceSomebodySetByHand() {
        let written = text(plan(rows: [
            row("JPN", "800", old: "600", source: .overrideAmount)
        ]))
        #expect(written.contains("set by hand"))
    }

    @Test func namesTheBandACurvePutACountryIn() {
        let written = text(plan(rows: [
            row("IND", "249", old: "199", source: .curve(band: "lower-middle income"))
        ]))
        #expect(written.contains("lower-middle income"))
    }

    /// A rounded price nobody was warned about reads as a mistake.
    @Test func printsTheRoundingRuleWithEveryPriceSection() {
        #expect(text(plan(rows: [row("USA", "5.99", old: "4.99")])).contains(".99"))
    }

    @Test func namesTheCountriesLeftOut() {
        let written = text(plan(
            rows: [row("USA", "5.99", old: "4.99")],
            skipped: [PriceResolver.Skipped(territory: "RUS", reason: "Not sold here.")]
        ))
        #expect(written.contains("Left out: RUS"))
    }

    // MARK: - Summary

    @Test func countsPricesAndProductFieldsInTheSummary() {
        let summary = ChangePlanFormatter.summary(plan(
            productText: [.init(
                productID: "com.example.pro", locale: "en-US", field: .name,
                action: .add, oldValue: nil, newValue: "Pro"
            )],
            rows: [row("USA", "5.99", old: "4.99")]
        ))
        #expect(summary.contains("1 in-app purchase field"))
        #expect(summary.contains("1 price in 1 product"))
        #expect(summary.contains(" and "))
    }
}
