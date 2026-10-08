import ASCKitAPI
import Foundation
import Testing
@testable import ASCKitProject

/// The digest is the consent token. Whatever a person read has to be what gets
/// written, so anything a push would do has to move it.
struct ProductDigestTests {
    func row(
        _ territory: String,
        _ amount: Money,
        old: Money? = nil,
        pointID: String? = nil,
        direction: ChangePlan.PriceChange.Direction = .up,
        planType: ChangePlan.PriceChange.PlanType = .upfront,
        source: PriceResolver.Source = .curve(band: nil),
        roundedUpBy: Money = "0"
    ) -> ChangePlan.PriceChange.Row {
        ChangePlan.PriceChange.Row(
            territory: territory,
            planType: planType,
            currency: "USD",
            pricePointID: pointID ?? "\(territory)-\(amount)",
            oldAmount: old,
            newAmount: amount,
            direction: direction,
            source: source,
            roundedUpBy: roundedUpBy
        )
    }

    func plan(
        productText: [ChangePlan.ProductTextChange] = [],
        rows: [ChangePlan.PriceChange.Row]? = nil,
        curveID: String = "purchasing-power",
        baseAmount: Money = "4.99",
        replacesWholeSchedule: Bool = false,
        preserveCurrentPrice: Bool? = true,
        skipped: [PriceResolver.Skipped] = [],
        newProducts: [String] = []
    ) -> ChangePlan {
        ChangePlan(
            versionString: "1.0",
            versionState: nil,
            textChanges: [],
            missingLocales: [],
            screenshotPlans: [],
            productTextChanges: productText,
            pricePlans: [ChangePlan.PriceChange(
                productID: "com.example.pro",
                kind: .autoRenewableSubscription,
                baseTerritory: "USA",
                baseAmount: baseAmount,
                curveID: curveID,
                replacesWholeSchedule: replacesWholeSchedule,
                preserveCurrentPrice: preserveCurrentPrice,
                rows: rows ?? [row("USA", "4.99", old: "3.99")],
                skipped: skipped
            )],
            newProducts: newProducts,
            blocked: [],
            skipped: []
        )
    }

    // MARK: - Prices

    @Test func staysTheSameForTwoPlansThatWouldDoTheSameThing() {
        #expect(plan().digest == plan().digest)
    }

    @Test func movesWhenACountrysPriceChanges() {
        #expect(plan().digest != plan(rows: [row("USA", "5.99", old: "3.99")]).digest)
    }

    /// Apple regenerates price point ids. A point that changed between somebody
    /// reading the plan and the push writing it is the exact surprise this
    /// exists to catch, even when the amount is identical.
    @Test func movesWhenThePricePointIdChangesAndTheAmountDoesNot() {
        let before = plan(rows: [row("USA", "4.99", pointID: "one")])
        let after = plan(rows: [row("USA", "4.99", pointID: "two")])
        #expect(before.digest != after.digest)
    }

    /// What a push compares leaves the identifier out, because a push writes
    /// the second read's plan and so sends the second read's identifiers. This
    /// is what lets a plan read off a kept ladder be pushed at all.
    @Test func theAgreementDoesNotMoveWhenOnlyThePricePointIdChanges() {
        let before = plan(rows: [row("USA", "4.99", pointID: "one")])
        let after = plan(rows: [row("USA", "4.99", pointID: "two")])
        #expect(before.agreementDigest == after.agreementDigest)
    }

    @Test func theAgreementMovesWhenACountrysPriceChanges() {
        let before = plan(rows: [row("USA", "4.99", old: "3.99")])
        let after = plan(rows: [row("USA", "5.99", old: "3.99")])
        #expect(before.agreementDigest != after.agreementDigest)
    }

    /// The number a plan calls "old" is what says whether a country is a rise,
    /// and a rise needs a second word for it.
    @Test func theAgreementMovesWhenTodaysPriceChanges() {
        let before = plan(rows: [row("USA", "4.99", old: "3.99")])
        let after = plan(rows: [row("USA", "4.99", old: "4.99")])
        #expect(before.agreementDigest != after.agreementDigest)
    }

    @Test func theAgreementMovesWhenACountryIsLeftOut() {
        let both = plan(rows: [row("USA", "4.99"), row("DEU", "5.99")])
        let one = plan(rows: [row("USA", "4.99")])
        #expect(both.agreementDigest != one.agreementDigest)
    }

    @Test func theAgreementMovesWhenOnlyWhereThePriceCameFromChanges() {
        let before = plan(rows: [row("USA", "4.99", source: .curve(band: nil))])
        let after = plan(rows: [row("USA", "4.99", source: .overrideAmount)])
        #expect(before.agreementDigest != after.agreementDigest)
    }

    /// A price that used to come from the curve and now comes from a hand-set
    /// override is a different decision, whatever the number says.
    @Test func movesWhenOnlyWhereThePriceCameFromChanges() {
        let before = plan(rows: [row("USA", "4.99", source: .curve(band: nil))])
        let after = plan(rows: [row("USA", "4.99", source: .overrideAmount)])
        #expect(before.digest != after.digest)
    }

    /// The plan prints twelve rows out of a hundred and seventy seven, so a
    /// change past the end of what was printed matters more here than anywhere
    /// else in this file.
    @Test func movesWhenACountryNobodySawOnScreenChanges() {
        let many = (1 ... 40).map { row("T\($0)", "1.99") }
        var moved = many
        moved[39] = row("T40", "2.99")
        #expect(plan(rows: many).digest != plan(rows: moved).digest)
    }

    @Test func movesWhenTheCurveChanges() {
        #expect(plan().digest != plan(curveID: "tier-anchored").digest)
    }

    @Test func movesWhenTheBasePriceChanges() {
        #expect(plan().digest != plan(baseAmount: "5.99").digest)
    }

    /// The two kinds write in opposite ways, so which one this is has to be
    /// part of what somebody agreed to.
    @Test func movesWhenTheWriteChangesFromMergingToReplacing() {
        #expect(plan().digest != plan(replacesWholeSchedule: true).digest)
    }

    /// Moving existing subscribers onto a new price cannot be undone, so it
    /// cannot change quietly between the plan and the write.
    @Test func movesWhenExistingSubscribersStopBeingProtected() {
        #expect(plan().digest != plan(preserveCurrentPrice: false).digest)
    }

    @Test func movesWhenACountryIsLeftOut() {
        let left = [PriceResolver.Skipped(territory: "RUS", reason: "Not sold here.")]
        #expect(plan().digest != plan(skipped: left).digest)
    }

    // MARK: - Words

    @Test func movesWhenAProductsWordsChange() {
        let before = plan(productText: [.init(
            productID: "com.example.pro", locale: "en-US", field: .name,
            action: .change, oldValue: "Old", newValue: "Pro"
        )])
        let after = plan(productText: [.init(
            productID: "com.example.pro", locale: "en-US", field: .name,
            action: .change, oldValue: "Old", newValue: "Pro Monthly"
        )])
        #expect(before.digest != after.digest)
    }

    @Test func movesWhenAProductAppearsThatTheStoreDoesNotHave() {
        #expect(plan().digest != plan(newProducts: ["com.example.new"]).digest)
    }

    // MARK: - What counts as a change at all

    @Test func readsAPlanWithOnlyPriceChangesAsNotEmpty() {
        #expect(plan().isEmpty == false)
        #expect(plan().hasPriceChanges)
    }

    @Test func readsAPlanWhereEveryCountryStaysTheSameAsEmpty() {
        let same = plan(rows: [row("USA", "4.99", old: "4.99", direction: .same)])
        #expect(same.hasPriceChanges == false)
        #expect(same.isEmpty)
    }

    @Test func gathersEveryCountryThatWouldPayMore() {
        let mixed = plan(rows: [
            row("USA", "5.99", old: "4.99", direction: .up),
            row("IND", "199", old: "299", direction: .down),
            row("DEU", "5.99", old: "5.99", direction: .same)
        ])
        #expect(mixed.priceRises.map(\.territory) == ["USA"])
    }
}
