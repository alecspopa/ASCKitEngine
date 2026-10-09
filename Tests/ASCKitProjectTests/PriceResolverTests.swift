import Foundation
import Testing
@testable import ASCKitProject

struct PriceResolverTests {
    // MARK: - Building a ladder to resolve against

    /// A ladder written as the prices it holds, so a test says what it means
    /// without arithmetic.
    func ladder(
        _ territory: String,
        _ amounts: [Money],
        currency: String = "USD"
    ) -> [PricePoint] {
        amounts.map { amount in
            PricePoint(
                id: "\(territory)-\(amount)",
                territory: territory,
                customerPrice: amount,
                currency: currency
            )
        }
    }

    func plan(
        base: Money = "4.99",
        curve: String = "purchasing-power",
        overrides: [String: Product.PricePlan.Override] = [:]
    ) -> Product.PricePlan {
        Product.PricePlan(
            baseTerritory: "USA",
            baseAmount: base,
            curve: curve,
            overrides: overrides
        )
    }

    func resolve(
        plan: Product.PricePlan,
        curve: PriceCurve = .purchasingPower,
        anchors: [String: Money],
        ladders: [String: [PricePoint]]
    ) -> PriceResolver.Resolution {
        PriceResolver.resolve(
            productID: "com.example.pro",
            plan: plan,
            curve: curve,
            anchors: anchors,
            ladders: ladders,
            territories: Array(ladders.keys)
        )
    }

    // MARK: - Rounding

    /// Up, never down. Rounding down charges less than the curve asked for, and
    /// the money lost is real.
    @Test func roundsUpToTheNextStep() {
        let points = ladder("USA", ["0.99", "1.99", "2.99", "3.99", "4.99"])
        let price = PriceResolver.roundedUp(from: "2.10", in: points)
        #expect(price?.customerPrice.description == "2.99")
    }

    @Test func roundsUpEvenWhenTheLowerStepIsMuchCloser() {
        let points = ladder("USA", ["0.99", "4.99"])
        let price = PriceResolver.roundedUp(from: "1.05", in: points)
        #expect(price?.customerPrice.description == "4.99")
    }

    /// A ladder steps through .49 and .99, and .99 is the ending to land on.
    @Test func stepsPastAFortyNineToReachTheNinetyNineAboveIt() {
        let points = ladder("USA", ["2.99", "3.49", "3.99", "4.49", "4.99"])
        let price = PriceResolver.roundedUp(from: "3.20", in: points)
        #expect(price?.customerPrice.description == "3.99")
    }

    /// One step past a .49 and no further, so rounding can never skip a whole
    /// tier looking for an ending it likes.
    @Test func staysOnAFortyNineWhenTheStepAboveItIsNotANinetyNine() {
        let points = ladder("USA", ["3.49", "5.49", "7.49"])
        let price = PriceResolver.roundedUp(from: "3.20", in: points)
        #expect(price?.customerPrice.description == "3.49")
    }

    /// Somebody who typed an exact price the store offers meant that price.
    @Test func takesAnAmountThatIsAlreadyAStepWhateverItEndsIn() {
        let points = ladder("USA", ["2.99", "3.49", "3.99"])
        let price = PriceResolver.roundedUp(from: "3.49", in: points)
        #expect(price?.customerPrice.description == "3.49")
    }

    /// The yen has no minor unit, so nothing on its ladder ends in .99 and the
    /// rule is simply the next step up.
    @Test func takesTheNextStepUpInACurrencyWithNoMinorUnit() {
        let points = ladder("JPN", ["100", "300", "500", "800"], currency: "JPY")
        let price = PriceResolver.roundedUp(from: "310", in: points)
        #expect(price?.customerPrice.description == "500")
    }

    @Test func takesTheTopStepWhenTheWholeLadderIsBelowTheTarget() {
        let points = ladder("USA", ["0.99", "1.99"])
        let price = PriceResolver.roundedUp(from: "9.99", in: points)
        #expect(price?.customerPrice.description == "1.99")
    }

    /// Apple's real dollar ladder, between 1.79 and 2.19. It holds .90 and
    /// .95 steps, and ASCKit lands only on .49 and .99.
    var denseDollars: [PricePoint] {
        ladder("USA", ["1.79", "1.89", "1.90", "1.95", "1.99", "2.00", "2.09", "2.19"])
    }

    /// A target just under .90 does not stop on .90 or .95.
    @Test func passesTheStepsThatEndInNinetyAndNinetyFive() {
        let price = PriceResolver.roundedUp(from: "1.895", in: denseDollars)
        #expect(price?.customerPrice.description == "1.99")
    }

    /// A curve that lands exactly on .90 still rounds up. Only a typed price
    /// is taken as it is.
    @Test func roundsUpACurveTargetThatIsExactlyANinetyStep() {
        let curve = PriceResolver.roundedUp(from: "1.90", in: denseDollars, takesAnyExactStep: false)
        let typed = PriceResolver.roundedUp(from: "1.90", in: denseDollars)
        #expect(curve?.customerPrice.description == "1.99")
        #expect(typed?.customerPrice == Money(string: "1.90"))
    }

    /// Above 50 the dollar ladder has .90 and .99 steps and no .49, so a price
    /// lands on the next .99.
    @Test func landsOnTheNextNinetyNineWhereThereIsNoFortyNine() {
        let points = ladder("USA", ["50.90", "50.99", "51.00", "51.90", "51.99"])
        let price = PriceResolver.roundedUp(from: "51.20", in: points)
        #expect(price?.customerPrice.description == "51.99")
    }

    /// The Swiss franc has no .49 or .99 step, so it takes the next step.
    @Test func takesTheNextStepInACurrencyWithNoFortyNineOrNinetyNine() {
        let points = ladder("CHE", ["10.50", "10.90", "10.95", "11.00"], currency: "CHF")
        let price = PriceResolver.roundedUp(from: "10.60", in: points)
        #expect(price?.customerPrice == Money(string: "10.90"))
    }

    @Test func findsNothingInAnEmptyLadder() {
        #expect(PriceResolver.roundedUp(from: "1.00", in: []) == nil)
    }

    @Test(arguments: [
        ("4.99", true), ("3.49", false), ("800", false),
        ("0.99", true), ("19.99", true), ("5.00", false)
    ])
    func knowsWhichAmountsEndInNinetyNine(amount: Money, ends: Bool) {
        #expect(amount.endsInNinetyNine == ends)
    }

    // MARK: - The instalment on a 12-month commitment

    /// Apple: the 12-month commitment total must be at least the upfront price
    /// and no more than 1.5 times it.
    @Test(arguments: [
        // yearly, instalment, allowed
        (Money("12"), Money("1"), true), // exactly the year
        (Money("12"), Money("1.5"), true), // exactly 1.5 times it
        (Money("12"), Money("1.51"), false), // over the cap
        (Money("12"), Money("0.99"), false), // under the year
        (Money("14.99"), Money("1.49"), true) // what the real product has
    ])
    func knowsWhichInstalmentsCanGoOutWithAYearlyPrice(
        yearly: Money, instalment: Money, allowed: Bool
    ) {
        #expect(PriceResolver.fits(yearly: yearly, instalment: instalment) == allowed)
    }

    /// The whole point: both prices move by the same factor, so a country keeps
    /// the split it already offers between paying at once and paying monthly.
    @Test func movesTheInstalmentByTheSameFactorAsTheYear() {
        // The real product's split: 14.99 for the year, 1.49 a month. Halve the
        // year and the instalment should halve too, to about 0.75.
        let ladder = ladder("DEU", ["0.49", "0.69", "0.79", "0.99"], currency: "EUR")
        let point = PriceResolver.instalment(
            matching: "7.49", wasYearly: "14.99", wasInstalment: "1.49", in: ladder
        )
        #expect(point?.customerPrice.description == "0.69")
    }

    /// Rounding is what breaks the rule, so the instalment is pulled back
    /// inside the band rather than left where the scale put it.
    @Test func refusesToPickAnInstalmentTheStoreWouldReject() throws {
        // Scaling alone would pick 1.99, and twelve of those come to 23.88
        // against a year of 12, which is well over the cap.
        let ladder = ladder("DEU", ["0.99", "1.29", "1.49", "1.99"], currency: "EUR")
        let point = try #require(PriceResolver.instalment(
            matching: "12", wasYearly: "24", wasInstalment: "2.99", in: ladder
        ))
        #expect(point.customerPrice.description == "1.49")
        #expect(PriceResolver.fits(yearly: "12", instalment: point.customerPrice))
    }

    /// The band is narrow: an instalment must sit between a twelfth and an
    /// eighth of the year. A coarse ladder can hold nothing in it at all, which
    /// is why the planner has to say so rather than send the year on its own.
    @Test func findsNothingWhenACoarseLadderMissesTheBand() {
        let coarse = ladder("JPN", ["100", "500", "1000"], currency: "JPY")
        #expect(PriceResolver.instalment(
            matching: "2400", wasYearly: "2500", wasInstalment: "210", in: coarse
        ) == nil)
    }

    /// A ladder with nothing the rule allows gives nothing, rather than giving
    /// something App Store Connect will refuse.
    @Test func findsNoInstalmentWhenTheLadderHasNoneThatFits() {
        let ladder = ladder("DEU", ["9.99", "19.99"], currency: "EUR")
        #expect(PriceResolver.instalment(
            matching: "12", wasYearly: "24", wasInstalment: "2.99", in: ladder
        ) == nil)
    }

    // MARK: - Saying so

    /// A rounded price nobody was warned about reads as a mistake, so the
    /// result carries the sentence rather than leaving each caller to remember.
    @Test func carriesTheRoundingRuleWithEveryResult() {
        let result = resolve(
            plan: plan(),
            anchors: ["USA": "4.99"],
            ladders: ["USA": ladder("USA", ["4.99"])]
        )
        #expect(result.roundingNote.contains(".99"))
        #expect(result.roundingNote.contains("rounds every price up"))
    }

    @Test func namesTheCountriesWhereRoundingMovedThePrice() {
        let result = resolve(
            plan: plan(),
            anchors: ["USA": "4.99", "IND": "449"],
            ladders: [
                "USA": ladder("USA", ["4.99"]),
                "IND": ladder("IND", ["199", "299"], currency: "INR")
            ]
        )
        #expect(result.rounded.map(\.territory) == ["IND"])
        #expect(result.rounded.first?.roundedUpBy.isPositive == true)
    }

    @Test func warnsWhenEvenTheTopOfTheLadderIsBelowWhatTheCurveAsksFor() {
        let result = resolve(
            plan: plan(base: "49.99"),
            anchors: ["USA": "49.99"],
            ladders: ["USA": ladder("USA", ["0.99", "1.99"])]
        )
        let usa = result.prices.first { $0.territory == "USA" }
        #expect(usa?.customerPrice.description == "1.99")
        #expect(usa?.belowTarget == true)
        #expect(result.problems.contains { $0.kind == .noPricePoint && $0.severity == .warning })
    }

    // MARK: - The curve

    /// Apple's price is the starting point for every curve, converted or not,
    /// because it is the only number that arrives in the right currency.
    @Test func startsFromApplesOwnPriceInTheRightCurrency() {
        let result = resolve(
            plan: plan(curve: "apple-equalized"),
            curve: .appleEqualized,
            anchors: ["IND": "449"],
            ladders: ["IND": ladder("IND", ["99", "149", "199", "249", "299", "449"],
                                    currency: "INR")]
        )
        let india = result.prices.first { $0.territory == "IND" }
        #expect(india?.customerPrice.description == "449")
        #expect(india?.multiplier == 1.0)
        #expect(india?.currency == "INR")
    }

    /// A converting curve takes Apple's number down to what the base price is
    /// worth at a market rate, then applies the band. Apple says 4.99 is worth
    /// 449 rupees, and a market conversion says rather less than that.
    @Test func pricesFromAConvertedBaseOnAConvertingCurve() {
        let result = resolve(
            plan: plan(),
            anchors: ["IND": "449"],
            ladders: ["IND": ladder("IND", ["99", "149", "199", "249", "299", "449"],
                                    currency: "INR")]
        )
        let india = result.prices.first { $0.territory == "IND" }
        let expected = USDConversion.ratio(for: "IND") * 0.55
        #expect(india?.multiplier == expected)
        #expect(india?.customerPrice.description == "249")
        #expect(india?.currency == "INR")
    }

    @Test func leavesTheBaseTerritoryOnApplesOwnPrice() {
        let result = resolve(
            plan: plan(),
            anchors: ["USA": "4.99"],
            ladders: ["USA": ladder("USA", ["3.99", "4.99", "5.99"])]
        )
        let usa = result.prices.first { $0.territory == "USA" }
        #expect(usa?.customerPrice.description == "4.99")
        #expect(usa?.multiplier == 1.0)
        #expect(usa?.roundedUpBy.description == "0")
    }

    @Test func saysWhichBandAPriceCameFrom() {
        let result = resolve(
            plan: plan(),
            anchors: ["IND": "449", "USA": "4.99"],
            ladders: [
                "IND": ladder("IND", ["249"], currency: "INR"),
                "USA": ladder("USA", ["4.99"])
            ]
        )
        let india = result.prices.first { $0.territory == "IND" }
        let usa = result.prices.first { $0.territory == "USA" }
        #expect(india?.source == .curve(band: "lower-middle income"))
        // The base country charges the base price, so its number comes from
        // there rather than from any band.
        #expect(usa?.source == .base)
    }

    /// You named that price for that country. A curve that scaled it would mean
    /// the number you wrote is not the number you get.
    @Test func chargesTheBasePriceInTheBaseCountryWhateverTheCurveSays() {
        let result = resolve(
            plan: plan(base: "4.99", curve: "proceeds-parity"),
            curve: .proceedsParity,
            anchors: ["USA": "4.99"],
            ladders: ["USA": ladder("USA", ["3.99", "4.99", "5.99"])]
        )

        let usa = result.prices.first { $0.territory == "USA" }
        #expect(usa?.customerPrice.description == "4.99")
        #expect(usa?.multiplier == 1.0)
        #expect(usa?.source == .base)
    }

    /// A converting curve prices from the base converted at a market rate, so
    /// what reaches the resolver is the conversion and the band together.
    @Test func multipliesByBothTheConversionAndTheBandOnAConvertingCurve() {
        let result = resolve(
            plan: plan(base: "14.99"),
            anchors: ["IND": "1499"],
            ladders: ["IND": ladder("IND", ["799", "829", "849"], currency: "INR")]
        )

        let india = result.prices.first { $0.territory == "IND" }
        let expected = USDConversion.ratio(for: "IND")
            * PriceCurve.purchasingPower.bandMultiplier(for: "IND")
        #expect(india?.multiplier == expected)
    }

    // MARK: - Overrides

    @Test func takesAnAmountSomebodyTypedAndSnapsItLikeAnyOther() {
        let result = resolve(
            plan: plan(overrides: [
                "JPN": .init(amount: "800", why: "600 reads as a converted price.")
            ]),
            anchors: ["JPN": "600"],
            ladders: ["JPN": ladder("JPN", ["400", "600", "800", "1000"], currency: "JPY")]
        )
        let japan = result.prices.first { $0.territory == "JPN" }
        #expect(japan?.customerPrice.description == "800")
        #expect(japan?.source == .overrideAmount)
    }

    @Test func takesAPricePointSomebodyNamedExactlyAsGiven() {
        let result = resolve(
            plan: plan(overrides: ["IND": .init(pricePoint: "IND-149", why: "Matched locally.")]),
            anchors: ["IND": "449"],
            ladders: ["IND": ladder("IND", ["99", "149", "449"], currency: "INR")]
        )
        let india = result.prices.first { $0.territory == "IND" }
        #expect(india?.customerPrice.description == "149")
        #expect(india?.source == .overridePricePoint)
        #expect(india?.roundedUpBy.description == "0")
    }

    /// A price point belongs to one product in one country. Quietly picking a
    /// nearby one instead would be a wrong price with no sign of it.
    @Test func refusesAPricePointThisProductDoesNotHave() {
        let result = resolve(
            plan: plan(overrides: ["IND": .init(pricePoint: "somebody-elses", why: "x")]),
            anchors: ["IND": "449"],
            ladders: ["IND": ladder("IND", ["99", "449"], currency: "INR")]
        )
        #expect(result.prices.isEmpty)
        #expect(result.hasErrors)
        #expect(result.problems.contains { $0.kind == .noPricePoint })
    }

    @Test func leavesOutATerritoryTheFileSaysToSkip() {
        let result = resolve(
            plan: plan(overrides: ["RUS": .init(skip: true, why: "Not sold here.")]),
            anchors: ["RUS": "400", "USA": "4.99"],
            ladders: [
                "RUS": ladder("RUS", ["400"], currency: "RUB"),
                "USA": ladder("USA", ["4.99"])
            ]
        )
        #expect(result.prices.map(\.territory) == ["USA"])
        #expect(result.skipped.map(\.territory) == ["RUS"])
        #expect(result.skipped.first?.reason.english == "Not sold here.")
    }

    /// A price nobody can explain a year later is the one that goes wrong.
    @Test func warnsAboutAPriceSetByHandWithNoReason() {
        let result = resolve(
            plan: plan(overrides: ["JPN": .init(amount: "800")]),
            anchors: ["JPN": "600"],
            ladders: ["JPN": ladder("JPN", ["800"], currency: "JPY")]
        )
        let warning = result.problems.first { $0.kind == .priceOverrideUnexplained }
        #expect(warning?.severity == .warning)
        #expect(warning?.territory == "JPN")
        #expect(result.hasErrors == false)
    }

    @Test func saysNothingAboutAnOverrideThatExplainsItself() {
        let result = resolve(
            plan: plan(overrides: ["JPN": .init(amount: "800", why: "Shelf price.")]),
            anchors: ["JPN": "600"],
            ladders: ["JPN": ladder("JPN", ["800"], currency: "JPY")]
        )
        #expect(result.problems.contains { $0.kind == .priceOverrideUnexplained } == false)
    }

    // MARK: - What is missing

    @Test func refusesATerritoryWithNoPricesToChooseFrom() {
        let result = resolve(
            plan: plan(),
            anchors: ["IND": "449"],
            ladders: ["IND": []]
        )
        #expect(result.hasErrors)
        #expect(result.problems.first { $0.kind == .noPricePoint }?.territory == "IND")
    }

    /// Without Apple's equivalent price there is nothing for a multiplier to
    /// multiply, so the country is left out rather than guessed at.
    @Test func leavesOutATerritoryApplesGivesNoEquivalentPriceFor() {
        let result = resolve(
            plan: plan(),
            anchors: [:],
            ladders: ["IND": ladder("IND", ["99", "449"], currency: "INR")]
        )
        #expect(result.prices.isEmpty)
        #expect(result.skipped.map(\.territory) == ["IND"])
        #expect(result.hasErrors == false)
    }

    @Test func warnsAboutACountryItsOwnTableDoesNotList() {
        let result = resolve(
            plan: plan(),
            anchors: ["XYZ": "10"],
            ladders: ["XYZ": ladder("XYZ", ["9.99", "10.99"])]
        )
        let warning = result.problems.first { $0.kind == .territoryNotKnown }
        #expect(warning?.severity == .warning)
        #expect(warning?.territory == "XYZ")
        // It still gets a price, at Apple's own rate, rather than being dropped.
        #expect(result.prices.map(\.territory) == ["XYZ"])
        #expect(result.prices.first?.multiplier == 1.0)
    }

    // MARK: - Order

    /// The change plan's digest walks these in order, so two runs that resolve
    /// the same prices have to produce the same list.
    @Test func sortsEveryCountryByItsCode() {
        let result = resolve(
            plan: plan(),
            anchors: ["USA": "4.99", "IND": "449",
                      "DEU": "5.99"],
            ladders: [
                "USA": ladder("USA", ["4.99"]),
                "IND": ladder("IND", ["249"], currency: "INR"),
                "DEU": ladder("DEU", ["5.99"], currency: "EUR")
            ]
        )
        #expect(result.prices.map(\.territory) == ["DEU", "IND", "USA"])
    }
}
