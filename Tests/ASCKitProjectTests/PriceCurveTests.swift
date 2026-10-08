import Foundation
import Testing
@testable import ASCKitProject

struct PriceCurveTests {
    // MARK: - The grouping the curves share

    /// A territory named in no group takes the base multiplier, and a territory
    /// named in two takes whichever band comes first. Either one is a price
    /// nobody chose, and neither shows up as an error anywhere else, so it is
    /// checked here.
    @Test func sortsEveryTerritoryIntoExactlyOneIncomeGroup() {
        let named = IncomeGroup.allNamed
        #expect(Set(named).count == named.count, "a territory is in two groups")
        #expect(Set(named) == Set(Territory.allIdentifiers))
    }

    @Test func namesOnlyRealTerritoriesInEveryBand() {
        for curve in PriceCurve.all {
            for band in curve.bands {
                for id in band.territories {
                    #expect(Territory.isKnown(id), "\(curve.id) names \(id), which is not a territory")
                }
            }
        }
    }

    @Test func namesNoTerritoryTwiceWithinOneCurve() {
        for curve in PriceCurve.all {
            let named = curve.namedTerritories
            #expect(Set(named).count == named.count, "\(curve.id) names a territory twice")
        }
    }

    // MARK: - The shape of a curve

    /// A territory nobody thought about gets Apple's own price. Anything else
    /// would quietly discount or quietly overcharge a country the day Apple
    /// adds one.
    @Test func fallsBackToApplesOwnPriceForATerritoryNoBandNames() {
        for curve in PriceCurve.all {
            #expect(curve.baseMultiplier == 1.0, "\(curve.id) does not fall back to Apple's price")
        }
    }

    @Test func chargesApplesOwnPriceEverywhereOnTheDefaultCurve() {
        let curve = PriceCurve.appleEqualized
        for id in Territory.allIdentifiers {
            #expect(curve.multiplier(for: id) == 1.0)
        }
    }

    /// The band's own number, without the conversion that rides on top of it.
    @Test func discountsByIncomeOnThePurchasingPowerCurve() {
        let curve = PriceCurve.purchasingPower
        #expect(curve.bandMultiplier(for: "USA") == 1.0)
        #expect(curve.bandMultiplier(for: "BRA") == 0.75)
        #expect(curve.bandMultiplier(for: "IND") == 0.55)
        #expect(curve.bandMultiplier(for: "AFG") == 0.35)
    }

    @Test func cutsHarderOnTheEmergingMarketCurveThanOnThePurchasingPowerOne() {
        for id in IncomeGroup.lowerMiddle + IncomeGroup.low {
            let gentle = PriceCurve.purchasingPower.multiplier(for: id)
            let hard = PriceCurve.emergingMarketPush.multiplier(for: id)
            #expect(hard < gentle, "\(id) is not cut harder")
        }
    }

    @Test func raisesRatherThanCutsOnTheEqualProceedsCurve() {
        let curve = PriceCurve.proceedsParity
        #expect(curve.multiplier(for: "USA") == 1.0)
        #expect(curve.multiplier(for: "HUN") > 1.0)
        for band in curve.bands {
            #expect(band.multiplier > 1.0, "\(band.describedAs) cuts the price")
        }
    }

    @Test func saysWhichBandATerritoryIsIn() {
        let band = PriceCurve.purchasingPower.band(for: "IND")
        #expect(band?.describedAs == "lower-middle income")
        #expect(PriceCurve.purchasingPower.band(for: "USA") == nil)
    }

    // MARK: - Finding one

    @Test func findsACurveByItsIdentifier() {
        #expect(PriceCurve.named("purchasing-power")?.id == "purchasing-power")
        #expect(PriceCurve.isKnown("purchasing-power"))
        #expect(PriceCurve.isKnown("nonesuch") == false)
    }

    /// Somebody asking for "the Netflix model" has to land on a curve. The
    /// alias finds it, and the file keeps the shape name.
    @Test(arguments: [
        ("netflix", "purchasing-power"), ("Spotify", "purchasing-power"),
        ("STREAMING", "purchasing-power"), ("automatic", "apple-equalized"),
        ("games", "emerging-market-push"), ("enterprise", "proceeds-parity")
    ])
    func findsACurveByACompanyOrAShorthandName(alias: String, curve: String) {
        #expect(PriceCurve.named(alias)?.id == curve)
    }

    // MARK: - Converting the base price first

    /// Apple's price is not a conversion, so a curve that multiplied it could
    /// not mean "a fraction of what home pays". The converting curves fold both
    /// steps into one number, and only their product ever leaves the method, so
    /// nothing can apply one and forget the other.
    @Test func foldsTheConversionIntoTheMultiplierOnAConvertingCurve() {
        let curve = PriceCurve.purchasingPower
        #expect(curve.convertsCurrency)

        let band = curve.bandMultiplier(for: "DEU")
        #expect(band == 1.0)
        #expect(curve.multiplier(for: "DEU") == USDConversion.ratio(for: "DEU") * band)
    }

    @Test func leavesApplesOwnPriceAloneOnTheCurveThatMeansIt() {
        #expect(PriceCurve.appleEqualized.convertsCurrency == false)
        #expect(PriceCurve.proceedsParity.convertsCurrency == false)
        for id in Territory.allIdentifiers {
            #expect(PriceCurve.appleEqualized.multiplier(for: id) == 1.0)
        }
    }

    /// A euro country is charged about 40 percent above the base price
    /// converted at a market rate, which is what makes the conversion worth
    /// doing at all.
    @Test func knowsThatApplesPriceIsWellAboveAStraightConversionInTheEuroCountries() {
        #expect(USDConversion.ratio(for: "DEU") < 0.75)
        #expect(USDConversion.ratio(for: "USA") == 1.0)
    }

    /// A country where Apple charges less than a straight conversion. Its ratio
    /// is above 1.00, so a converting curve raises the price rather than
    /// lowering it, and that is worth being true rather than clamped away.
    @Test func keepsARatioAboveOneWhereApplesPriceIsBelowAConversion() {
        #expect(USDConversion.ratio(for: "QAT") > 1.0)
    }

    @Test func convertsAtParForACountryItHasNoRatioFor() {
        #expect(USDConversion.ratio(for: "ZZZ") == 1.0)
    }

    @Test func hasARatioForEveryTerritory() {
        for id in Territory.allIdentifiers where USDConversion.ratios[id] == nil {
            // Not a failure: a country the store added since the ratios were
            // measured converts at par until they are measured again.
            #expect(USDConversion.ratio(for: id) == 1.0)
        }
        #expect(USDConversion.ratios.count > 150)
    }

    @Test func saysWhenTheConversionWasMeasured() {
        #expect(USDConversion.provenance.takenOn.count == 10)
        #expect(USDConversion.provenance.source.contains("exchangerate-api.com"))
    }

    @Test func givesEveryCurveADistinctIdentifierAndNoClashingAlias() {
        let ids = PriceCurve.allIdentifiers
        #expect(Set(ids).count == ids.count)

        let aliases = PriceCurve.all.flatMap(\.aliases).map { $0.lowercased() }
        #expect(Set(aliases).count == aliases.count, "two curves answer to one alias")
        #expect(Set(aliases).isDisjoint(with: Set(ids)), "an alias is also an identifier")
    }

    @Test func saysWhereEveryCurvesNumbersCameFromAndWhen() {
        for curve in PriceCurve.all {
            #expect(curve.provenance.source.isEmpty == false)
            #expect(curve.provenance.takenOn.count == 10, "\(curve.id) has no dated provenance")
        }
    }
}
