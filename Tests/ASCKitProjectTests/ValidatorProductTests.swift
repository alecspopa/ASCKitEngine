import Foundation
import Testing
@testable import ASCKitProject

final class ValidatorProductTests {
    let fixture: FixtureProject

    init() throws {
        fixture = try FixtureProject()
        _ = try fixture.writeConfig(ProjectConfig(
            bundleID: "com.example.MyApp",
            keyID: "ABC123",
            locales: ["en-US", "de-DE"]
        ))
    }

    deinit {
        fixture.remove()
    }

    func check(_ product: Product) throws -> [Problem] {
        try fixture.writeProduct(product)
        let project = try fixture.load()
        return Validator(config: project.config).validate(ProductStore.load(in: project))
    }

    func subscription(
        status: AppInformation.Status = .approved,
        group: String? = "Pro",
        period: String? = "ONE_MONTH",
        localizations: [String: Product.Localization]? = nil,
        price: Product.PricePlan? = nil
    ) -> Product {
        Product(
            productID: "com.example.pro.monthly",
            kind: Product.Kind.autoRenewableSubscription.rawValue,
            subscriptionGroup: group,
            subscriptionPeriod: period,
            status: status,
            price: price ?? Product.PricePlan(
                baseTerritory: "USA",
                baseAmount: Money("4.99"),
                curve: "purchasing-power"
            ),
            localizations: localizations ?? [
                "en-US": .init(name: "Pro Monthly", description: "Everything in Pro, monthly."),
                "de-DE": .init(name: "Pro Monatlich", description: "Alles in Pro, monatlich.")
            ]
        )
    }

    // MARK: - Nothing wrong

    @Test func saysNothingAboutAProductThatIsFine() throws {
        try fixture.writeGroup()
        #expect(try check(subscription()).isEmpty)
    }

    // MARK: - What kind of purchase it is

    @Test func refusesAKindItDoesNotKnow() throws {
        var product = subscription()
        product.kind = "subscription"
        let problems = try check(product)
        #expect(problems.errors.contains { $0.kind == .productKindNotKnown })
        // The message has to say what the choices are, or a refusal helps nobody.
        #expect(problems.first { $0.kind == .productKindNotKnown }?
            .fix?.english.contains("auto_renewable_subscription") == true)
    }

    @Test func refusesASubscriptionWithNoGroup() throws {
        let problems = try check(subscription(group: nil))
        #expect(problems.errors.contains { $0.kind == .subscriptionHasNoGroup })
    }

    @Test func refusesAOneTimePurchaseThatNamesAGroup() throws {
        var product = subscription()
        product.kind = Product.Kind.nonConsumable.rawValue
        let problems = try check(product)
        #expect(problems.errors.contains { $0.kind == .nonSubscriptionNamesGroup })
    }

    /// Only a subscription has customers who already pay, so only a
    /// subscription can preserve what they pay.
    @Test func refusesPreserveCurrentPriceOnAOneTimePurchase() throws {
        var product = subscription(group: nil, period: nil)
        product.kind = Product.Kind.nonConsumable.rawValue
        product.price = Product.PricePlan(
            baseTerritory: "USA",
            baseAmount: Money("49.99"),
            curve: "tier-anchored",
            preserveCurrentPrice: true
        )
        let problems = try check(product)
        #expect(problems.errors.contains { $0.kind == .nonSubscriptionPreservesPrice })
    }

    @Test func warnsAboutASubscriptionThatDoesNotSayHowLongAPeriodIs() throws {
        let problems = try check(subscription(period: nil))
        #expect(problems.warnings.contains { $0.kind == .subscriptionHasNoPeriod })
    }

    // MARK: - The words a buyer reads

    /// The description is 45 characters. It is the number people get wrong.
    @Test func refusesADescriptionOverFortyFiveCharacters() throws {
        let tooLong = String(repeating: "a", count: 46)
        let problems = try check(subscription(localizations: [
            "en-US": .init(name: "Pro Monthly", description: tooLong),
            "de-DE": .init(name: "Pro Monatlich", description: "Alles in Pro.")
        ]))
        let problem = problems.first { $0.productField == .description && $0.locale == "en-US" }
        #expect(problem?.severity == .error)
        #expect(problem?.message.english.contains("46 characters") == true)
        #expect(problem?.fix?.english == "Cut 1 character.")
    }

    @Test func refusesANameOverThirtyCharacters() throws {
        let problems = try check(subscription(localizations: [
            "en-US": .init(name: String(repeating: "a", count: 31), description: "Fine."),
            "de-DE": .init(name: "Pro", description: "Gut.")
        ]))
        #expect(problems.errors.contains { $0.productField == .name })
    }

    /// App Store Connect needs both fields in every language, so a missing one
    /// is not "leave it alone" the way a listing field is.
    @Test func refusesAMissingDescriptionOnAProductThatWouldPublish() throws {
        let problems = try check(subscription(localizations: [
            "en-US": .init(name: "Pro Monthly", description: "Everything."),
            "de-DE": .init(name: "Pro Monatlich")
        ]))
        let problem = problems.first { $0.kind == .productTextNotTranslated }
        #expect(problem?.severity == .error)
        #expect(problem?.locale == "de-DE")
        #expect(problem?.productField == .description)
    }

    /// A draft is somebody's unfinished work, not a mistake.
    @Test func onlyWarnsAboutAMissingDescriptionWhileTheProductIsADraft() throws {
        let problems = try check(subscription(status: .draft, localizations: [
            "en-US": .init(name: "Pro Monthly", description: "Everything.")
        ]))
        let problem = problems.first { $0.kind == .productTextNotTranslated }
        #expect(problem?.severity == .warning)
    }

    @Test func saysNothingAboutAProductNobodyHasStartedWriting() throws {
        let problems = try check(subscription(status: .draft, localizations: [:]))
        #expect(problems.contains { $0.kind == .productTextNotTranslated } == false)
    }

    // MARK: - Words that never got translated

    @Test func warnsWhenADescriptionIsStillTheSourceLanguagesWordForWord() throws {
        let problems = try check(subscription(localizations: [
            "en-US": .init(name: "Pro Monthly", description: "Everything in Pro."),
            "de-DE": .init(name: "Pro Monatlich", description: "Everything in Pro.")
        ]))
        let problem = problems.first { $0.kind == .productTextMatchesSource }

        #expect(problem?.severity == .warning)
        #expect(problem?.locale == "de-DE")
        #expect(problem?.productField == .description)
    }

    /// A name is words somebody reads, so German writing the English one is
    /// worth the same warning a copied description gets.
    @Test func warnsWhenANameIsStillTheSourceLanguagesWordForWord() throws {
        let problems = try check(subscription(localizations: [
            "en-US": .init(name: "Pro Monthly", description: "Everything in Pro."),
            "de-DE": .init(name: "Pro Monthly", description: "Alles in Pro.")
        ]))
        let problem = problems.first { $0.kind == .productTextMatchesSource }

        #expect(problem?.severity == .warning)
        #expect(problem?.locale == "de-DE")
        #expect(problem?.productField == .name)
    }

    @Test func saysNothingWhenBothLanguagesReadTheSameWords() throws {
        _ = try fixture.writeConfig(ProjectConfig(
            bundleID: "com.example.MyApp",
            keyID: "ABC123",
            locales: ["en-US", "en-GB"]
        ))

        let problems = try check(subscription(localizations: [
            "en-US": .init(name: "Pro Monthly", description: "Everything in Pro."),
            "en-GB": .init(name: "Pro Monthly", description: "Everything in Pro.")
        ]))

        #expect(problems.contains { $0.kind == .productTextMatchesSource } == false)
    }

    @Test func refusesAnEmptyName() throws {
        let problems = try check(subscription(localizations: [
            "en-US": .init(name: "", description: "Everything."),
            "de-DE": .init(name: "Pro", description: "Alles.")
        ]))
        #expect(problems.errors.contains { $0.kind == .productTextEmpty && $0.productField == .name })
    }

    @Test func warnsAboutALanguageTheProjectDoesNotShip() throws {
        let problems = try check(subscription(localizations: [
            "en-US": .init(name: "Pro Monthly", description: "Everything."),
            "de-DE": .init(name: "Pro Monatlich", description: "Alles."),
            "fr-FR": .init(name: "Pro Mensuel", description: "Tout.")
        ]))
        #expect(problems.warnings.contains { $0.locale == "fr-FR" })
    }

    // MARK: - Prices

    @Test func refusesACurveItDoesNotKnow() throws {
        let problems = try check(subscription(price: Product.PricePlan(
            baseTerritory: "USA",
            baseAmount: Money("4.99"),
            curve: "netlfix"
        )))
        let problem = problems.first { $0.area == .pricing }
        #expect(problem?.severity == .error)
        #expect(problem?.fix?.english.contains("purchasing-power") == true)
    }

    /// A company name is a way to find a curve, so asking for one is not a
    /// mistake.
    @Test func acceptsACurveAskedForByACompanyName() throws {
        let problems = try check(subscription(price: Product.PricePlan(
            baseTerritory: "USA",
            baseAmount: Money("4.99"),
            curve: "netflix"
        )))
        #expect(problems.filter { $0.area == .pricing }.isEmpty)
    }

    /// Every other code in this project is two letters, so this is the mistake
    /// people make. The refusal has to name what they meant.
    @Test func refusesATwoLetterCountryCodeAndSaysTheThreeLetterOne() throws {
        let problems = try check(subscription(price: Product.PricePlan(
            baseTerritory: "US",
            baseAmount: Money("4.99"),
            curve: "purchasing-power"
        )))
        let problem = problems.first { $0.territory == "US" }
        #expect(problem?.severity == .error)
        #expect(problem?.fix?.english.contains("USA") == true)
    }

    @Test func refusesAPriceOfZero() throws {
        let problems = try check(subscription(price: Product.PricePlan(
            baseTerritory: "USA",
            baseAmount: Money("0"),
            curve: "purchasing-power"
        )))
        #expect(problems.errors.contains { $0.kind == .baseAmountNotANumber })
    }

    @Test func refusesAnOverrideForACountryThatDoesNotExist() throws {
        let problems = try check(subscription(price: Product.PricePlan(
            baseTerritory: "USA",
            baseAmount: Money("4.99"),
            curve: "purchasing-power",
            overrides: ["XYZ": .init(amount: Money("1"), why: "Because.")]
        )))
        #expect(problems.errors.contains { $0.territory == "XYZ" })
    }

    /// An amount is snapped and a price point is taken as it is, so naming both
    /// leaves nothing to decide which one wins.
    @Test func refusesAnOverrideThatNamesBothAnAmountAndAPricePoint() throws {
        let problems = try check(subscription(price: Product.PricePlan(
            baseTerritory: "USA",
            baseAmount: Money("4.99"),
            curve: "purchasing-power",
            overrides: ["JPN": .init(amount: Money("800"),
                                     pricePoint: "abc", why: "Because.")]
        )))
        #expect(problems.errors.contains { $0.kind == .overrideSaysBoth })
    }

    @Test func warnsAboutAnOverrideThatSaysNothing() throws {
        let problems = try check(subscription(price: Product.PricePlan(
            baseTerritory: "USA",
            baseAmount: Money("4.99"),
            curve: "purchasing-power",
            overrides: ["JPN": .init(why: "Because.")]
        )))
        #expect(problems.warnings.contains { $0.kind == .overrideSaysNothing })
    }

    @Test func refusesAStartDateItCannotRead() throws {
        let problems = try check(subscription(price: Product.PricePlan(
            baseTerritory: "USA",
            baseAmount: Money("4.99"),
            curve: "purchasing-power",
            startDate: "next Tuesday"
        )))
        #expect(problems.errors.contains { $0.kind == .startDateNotADate })
    }

    @Test func acceptsAStartDateWrittenTheWayItAsksFor() throws {
        let problems = try check(subscription(price: Product.PricePlan(
            baseTerritory: "USA",
            baseAmount: Money("4.99"),
            curve: "purchasing-power",
            startDate: "2027-01-01"
        )))
        #expect(problems.filter { $0.area == .pricing }.isEmpty)
    }

    // MARK: - Files

    @Test func refusesAProductFileItCannotRead() throws {
        try fixture.writeRawProduct("{ not json", named: "com.example.broken.json")
        let project = try fixture.load()
        let problems = Validator(config: project.config).validate(ProductStore.load(in: project))
        #expect(problems.errors.contains { $0.productID == "com.example.broken" })
    }

    @Test func warnsWhenTheFileNameAndTheProductIdDisagree() throws {
        try fixture.writeProduct(subscription(), named: "com.example.other.json")
        let project = try fixture.load()
        let problems = Validator(config: project.config).validate(ProductStore.load(in: project))
        let problem = problems.first { $0.productID == "com.example.other" }
        #expect(problem?.severity == .warning)
        #expect(problem?.fix?.english.contains("Rename the file") == true)
    }
}
