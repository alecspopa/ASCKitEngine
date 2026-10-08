import Foundation
import Testing
@testable import ASCKitProject

struct TerritoryTests {
    @Test func namesNoTerritoryTwice() {
        let ids = Territory.allIdentifiers
        #expect(Set(ids).count == ids.count)

        let codes = Territory.all.map(\.regionCode)
        #expect(Set(codes).count == codes.count)
    }

    /// The three-letter code is the App Store Connect identifier and the
    /// two-letter one is what `Locale` knows. A row that pairs them wrongly
    /// would put a real price on the wrong country, so the pairing is checked
    /// rather than trusted.
    @Test func pairsEveryTerritoryWithARealRegion() {
        let known = Set(Locale.Region.isoRegions.map(\.identifier))
        for territory in Territory.all {
            #expect(known.contains(territory.regionCode), "\(territory.id) has no such region")
        }
    }

    @Test func writesEveryIdentifierAsThreeCapitalLetters() {
        for territory in Territory.all {
            #expect(territory.id.count == 3, "\(territory.id) is not three letters")
            #expect(territory.id == territory.id.uppercased())
            #expect(territory.regionCode.count == 2)
            #expect(territory.regionCode == territory.regionCode.uppercased())
        }
    }

    @Test func readsANameOutOfTheSystemRatherThanOutOfTheTable() {
        #expect(Territory.named("DEU")?.englishName == "Germany")
        #expect(Territory.named("CIV")?.englishName.hasPrefix("C") == true)
    }

    @Test func keepsTheAppStoreSellingInAboutAHundredAndSeventyFivePlaces() {
        #expect(Territory.all.count > 160)
        #expect(Territory.all.count < 200)
    }

    // MARK: - Finding one

    @Test func findsATerritoryByItsIdentifier() {
        #expect(Territory.named("USA")?.regionCode == "US")
        #expect(Territory.isKnown("USA"))
        #expect(Territory.isKnown("XYZ") == false)
    }

    /// A refusal that names the code somebody meant is worth more than one that
    /// only says no. The two-letter code is the mistake people make, because
    /// every other code in this project is two letters.
    @Test(arguments: [("us", "USA"), ("US", "USA"), ("DE", "DEU"), ("gbr", "GBR")])
    func suggestsTheIdentifierSomebodyMeant(written: String, meant: String) {
        #expect(Territory.suggestion(for: written) == meant)
    }

    @Test func writesEveryCurrencyAsAnISOCode() {
        let known = Set(Locale.Currency.isoCurrencies.map(\.identifier))
        for territory in Territory.all {
            #expect(known.contains(territory.currency), "\(territory.id) has no such currency \(territory.currency)")
        }
    }

    /// `Locale` says Serbia pays in RSD and Kenya in KES. App Store Connect
    /// bills them in EUR and USD, and the price shows what Apple bills.
    @Test(arguments: [("SRB", "EUR"), ("KEN", "USD"), ("DEU", "EUR"), ("JPN", "JPY")])
    func holdsTheCurrencyAppStoreConnectBillsIn(id: String, currency: String) {
        #expect(Territory.named(id)?.currency == currency)
    }

    @Test(arguments: [
        ("en_US", "USD", "12.13", "$12.13"),
        ("de_DE", "EUR", "12.13", "12,13\u{00A0}€"),
        ("ja_JP", "JPY", "1200", "¥1,200")
    ])
    func formatsAnAmountInTheReadersLocale(
        locale: String, currency: String, written: String, expected: String
    ) throws {
        let amount = try #require(Money(string: written))
        #expect(amount.formatted(currency: currency, locale: Locale(identifier: locale)) == expected)
    }

    @Test func formatsAnAmountWithNoCurrencyAsANumber() throws {
        let amount = try #require(Money(string: "1234.5"))
        #expect(amount.formatted(currency: nil, locale: Locale(identifier: "de_DE")) == "1.234,5")
    }

    @Test func suggestsNothingForACodeItCannotPlace() {
        #expect(Territory.suggestion(for: "USA") == nil)
        #expect(Territory.suggestion(for: "ZZZZ") == nil)
    }
}
