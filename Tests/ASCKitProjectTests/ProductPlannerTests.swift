import ASCKitAPI
import Foundation
import Testing
@testable import ASCKitProject

struct ProductPlannerTests {
    let config = ProjectConfig(
        bundleID: "com.example.MyApp",
        keyID: "ABC123",
        locales: ["en-US", "de-DE"]
    )

    // MARK: - Building the two sides

    func onDisk(
        _ product: Product = ProductPlannerTests.subscription()
    ) -> ProductCatalog {
        ProductCatalog(products: [product.productID: product])
    }

    static func subscription(
        status: AppInformation.Status = .approved,
        kind: Product.Kind = .autoRenewableSubscription,
        price: Product.PricePlan? = nil,
        localizations: [String: Product.Localization]? = nil
    ) -> Product {
        Product(
            productID: "com.example.pro",
            kind: kind.rawValue,
            subscriptionGroup: kind.isAutoRenewable ? "Pro" : nil,
            status: status,
            price: price,
            localizations: localizations ?? [
                "en-US": .init(name: "Pro", description: "Everything in Pro."),
                "de-DE": .init(name: "Pro", description: "Alles in Pro.")
            ]
        )
    }

    /// A draft by default, which is what a product being worked on looks like.
    /// Its words cannot be planned without one, because ASCKit writes into a
    /// version and never makes one.
    func onStore(
        state: String? = "APPROVED",
        kind: String = "auto_renewable_subscription",
        version: RemoteProductVersion? = RemoteProductVersion(id: "v1", number: 3, state: .prepareForSubmission),
        localizations: [String: RemoteProductLocalization] = [:]
    ) -> RemoteProducts {
        RemoteProducts(
            appID: "a1",
            products: [RemoteProduct(
                id: "s1",
                productID: "com.example.pro",
                kind: kind,
                state: state,
                subscriptionGroup: "Pro",
                version: version,
                localizations: localizations
            )],
            groupNames: [:]
        )
    }

    func ladder(_ territory: String, _ amounts: [Money]) -> [PricePoint] {
        amounts.map {
            PricePoint(id: "\(territory)-\($0)", territory: territory, customerPrice: $0)
        }
    }

    // MARK: - Words

    @Test func addsAFieldTheStoreHasNothingFor() {
        let outcome = ProductPlanner.plan(local: onDisk(), config: config, remote: onStore())
        let change = outcome.textChanges.first { $0.locale == "en-US" && $0.field == .name }
        #expect(change?.action == .add)
        #expect(change?.newValue == "Pro")
    }

    @Test func changesAFieldTheStoreHoldsSomethingElseFor() {
        let outcome = ProductPlanner.plan(
            local: onDisk(),
            config: config,
            remote: onStore(localizations: [
                "en-US": .init(id: "l1", locale: "en-US", name: "Old", description: "Old words.")
            ])
        )
        let change = outcome.textChanges.first { $0.locale == "en-US" && $0.field == .name }
        #expect(change?.action == .change)
        #expect(change?.oldValue == "Old")
    }

    @Test func saysNothingAboutAFieldThatAlreadyMatches() {
        let outcome = ProductPlanner.plan(
            local: onDisk(),
            config: config,
            remote: onStore(localizations: [
                "en-US": .init(id: "l1", locale: "en-US", name: "Pro",
                               description: "Everything in Pro."),
                "de-DE": .init(id: "l2", locale: "de-DE", name: "Pro",
                               description: "Alles in Pro.")
            ])
        )
        #expect(outcome.textChanges.isEmpty)
    }

    /// Apple answers with an empty string for a field nobody ever set.
    @Test func readsAnEmptyRemoteValueAsSomethingToAddRatherThanToChange() {
        let outcome = ProductPlanner.plan(
            local: onDisk(),
            config: config,
            remote: onStore(localizations: [
                "en-US": .init(id: "l1", locale: "en-US", name: "", description: "")
            ])
        )
        #expect(outcome.textChanges.allSatisfy { $0.action == .add })
    }

    // MARK: - What a push refuses

    @Test func leavesOutAProductNobodyHasApproved() {
        let outcome = ProductPlanner.plan(
            local: onDisk(Self.subscription(status: .draft)),
            config: config,
            remote: onStore()
        )
        #expect(outcome.textChanges.isEmpty)
        #expect(outcome.skipped.first?.reason.english == "marked draft")
    }

    /// A product id is permanent and is compiled into the shipping app, and App
    /// Store Connect cannot delete a purchase at all.
    @Test func refusesToMakeAProductTheStoreDoesNotHave() {
        let outcome = ProductPlanner.plan(
            local: onDisk(),
            config: config,
            remote: RemoteProducts(appID: "a1", products: [], groupNames: [:])
        )
        #expect(outcome.newProducts == ["com.example.pro"])
        #expect(outcome.blocked.first?.reason.english.contains("never makes one") == true)
        #expect(outcome.textChanges.isEmpty)
    }

    @Test(arguments: ["IN_REVIEW", "WAITING_FOR_REVIEW", "PENDING_BINARY_APPROVAL"])
    func refusesAChangeWhileAppleIsLookingAtTheProduct(state: String) {
        let outcome = ProductPlanner.plan(
            local: onDisk(),
            config: config,
            remote: onStore(state: state)
        )
        #expect(outcome.blocked.first?.affects.english == "com.example.pro")
        #expect(outcome.textChanges.isEmpty)
    }

    // MARK: - Prices

    func priced(
        kind: Product.Kind = .autoRenewableSubscription,
        curve: String = "purchasing-power",
        preserveCurrentPrice: Bool? = nil,
        current: [String: Money] = [:]
    ) -> ProductPlanner.Outcome {
        let plan = Product.PricePlan(
            baseTerritory: "USA",
            baseAmount: "4.99",
            curve: curve,
            preserveCurrentPrice: preserveCurrentPrice
        )
        return ProductPlanner.plan(
            local: onDisk(Self.subscription(kind: kind, price: plan)),
            config: config,
            remote: onStore(kind: kind.rawValue),
            prices: ProductPlanner.Prices(
                anchors: ["com.example.pro": ["USA": "4.99", "IND": "449"]],
                ladders: ["com.example.pro": [
                    "USA": ladder("USA", ["3.99", "4.99", "5.99"]),
                    "IND": ladder("IND", ["199", "249", "299", "449"])
                ]],
                current: ["com.example.pro": current]
            )
        )
    }

    @Test func worksOutOnePriceForEveryCountryItHasALadderFor() {
        let change = priced().pricePlans.first
        #expect(change?.rows.map(\.territory) == ["IND", "USA"])
        #expect(change?.rows.first { $0.territory == "IND" }?.newAmount.description == "249")
    }

    @Test func saysWhetherEachCountryGoesUpOrDown() {
        let outcome = priced(current: ["USA": "3.99", "IND": "299"])
        let rows = outcome.pricePlans.first?.rows ?? []
        #expect(rows.first { $0.territory == "USA" }?.direction == .up)
        #expect(rows.first { $0.territory == "IND" }?.direction == .down)
    }

    @Test func callsACountryNewWhenTheStoreChargesNothingThereYet() {
        let outcome = priced(current: ["USA": "4.99"])
        let rows = outcome.pricePlans.first?.rows ?? []
        #expect(rows.first { $0.territory == "USA" }?.direction == .same)
        #expect(rows.first { $0.territory == "IND" }?.direction == .new)
    }

    /// The two kinds are opposite, and confusing them reprices a hundred
    /// countries without saying so.
    @Test func saysASubscriptionIsWrittenCountryByCountry() {
        #expect(priced(kind: .autoRenewableSubscription)
            .pricePlans.first?.replacesWholeSchedule == false)
    }

    @Test func saysAOneTimePurchaseReplacesTheWholeSchedule() {
        #expect(priced(kind: .nonConsumable)
            .pricePlans.first?.replacesWholeSchedule == true)
    }

    @Test func keepsExistingSubscribersOnTheirPriceUnlessToldOtherwise() {
        #expect(priced().pricePlans.first?.preserveCurrentPrice == true)
        #expect(priced(preserveCurrentPrice: false)
            .pricePlans.first?.preserveCurrentPrice == false)
    }

    /// Only a subscription has customers who already pay.
    @Test func saysNothingAboutExistingCustomersForAOneTimePurchase() {
        #expect(priced(kind: .nonConsumable).pricePlans.first?.preserveCurrentPrice == nil)
    }

    @Test func refusesToPlanAPriceItHasReadNoLadderFor() {
        let plan = Product.PricePlan(baseTerritory: "USA", baseAmount: "4.99", curve: "purchasing-power")
        let outcome = ProductPlanner.plan(
            local: onDisk(Self.subscription(price: plan)),
            config: config,
            remote: onStore()
        )
        #expect(outcome.pricePlans.isEmpty)
        #expect(outcome.blocked.first?.reason.english.contains("no prices read") == true)
    }

    /// The validator already names the choices, so saying it twice in one run
    /// would only be noise.
    @Test func leavesACurveItDoesNotKnowToTheValidator() {
        let outcome = priced(curve: "netlfix")
        #expect(outcome.pricePlans.isEmpty)
        #expect(outcome.blocked.isEmpty)
    }
}
