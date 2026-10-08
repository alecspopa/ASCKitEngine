import ASCKitAPI
import Foundation
import Testing
@testable import ASCKitProject

final class SubscriptionGroupDriftTests {
    let fixture: FixtureProject

    let config = ProjectConfig(
        bundleID: "com.example.MyApp",
        keyID: "ABC123",
        locales: ["en-US", "de-DE"]
    )

    init() throws {
        fixture = try FixtureProject()
        _ = try fixture.writeConfig(config)
    }

    deinit {
        fixture.remove()
    }

    func subscription(id: String = "com.example.monthly", group: String = "Premium") -> Product {
        Product(
            productID: id,
            kind: Product.Kind.autoRenewableSubscription.rawValue,
            subscriptionGroup: group,
            subscriptionPeriod: "ONE_MONTH",
            status: .approved,
            localizations: ["en-US": .init(name: "Monthly", description: "Everything, monthly.")]
        )
    }

    func premium() -> SubscriptionGroup {
        SubscriptionGroup(
            referenceName: "Premium",
            status: .approved,
            localizations: ["en-US": .init(name: "Premium"), "de-DE": .init(name: "Premium Abo")]
        )
    }

    /// The store after somebody renamed Premium to Plus.
    func remote(
        groups: [RemoteSubscriptionGroup] = [RemoteSubscriptionGroup(
            id: "g1",
            referenceName: "Plus",
            version: RemoteProductVersion(id: "v1", number: 3, state: .prepareForSubmission)
        )],
        products: [String: String] = ["com.example.monthly": "Plus"]
    ) -> RemoteProducts {
        RemoteProducts(
            appID: "a1",
            products: products.sorted { $0.key < $1.key }.map { productID, group in
                RemoteProduct(
                    id: "s-\(productID)",
                    productID: productID,
                    kind: "auto_renewable_subscription",
                    subscriptionGroup: group,
                    version: RemoteProductVersion(
                        id: "pv1", number: 3, state: .prepareForSubmission
                    )
                )
            },
            groupNames: Dictionary(uniqueKeysWithValues: groups.map { ($0.id, $0.referenceName) }),
            groups: groups
        )
    }

    func follow(_ remote: RemoteProducts) throws -> SubscriptionGroupDrift.Followed {
        let project = try fixture.load()
        let drift = SubscriptionGroupDrift.compare(local: ProductStore.load(in: project), remote: remote)
        return try SubscriptionGroupDrift.follow(drift, from: remote, in: project)
    }

    // MARK: - Comparing

    @Test func findsTheNameTheStoreGivesTheSubscriptions() {
        let drift = SubscriptionGroupDrift.compare(
            local: ProductCatalog(
                products: ["com.example.monthly": subscription()],
                groups: ["Premium": premium()]
            ),
            remote: remote()
        )

        #expect(drift.renames == [.init(from: "Premium", to: "Plus", productIDs: ["com.example.monthly"])])
        #expect(drift.gone.isEmpty)
    }

    @Test func callsAGroupWithNoSubscriptionGone() {
        let drift = SubscriptionGroupDrift.compare(
            local: ProductCatalog(groups: ["Premium": premium()]),
            remote: remote(products: [:])
        )

        #expect(drift.renames.isEmpty)
        #expect(drift.gone == ["Premium"])
    }

    @Test func agreesWhenTheStoreHoldsTheName() {
        let drift = SubscriptionGroupDrift.compare(
            local: ProductCatalog(
                products: ["com.example.monthly": subscription(group: "Plus")],
                groups: ["Plus": premium()]
            ),
            remote: remote()
        )
        #expect(drift.agrees)
    }

    /// Nothing says what the group is called now, and its subscriptions are
    /// somebody's work, so the file stays.
    @Test func leavesAGroupWhoseSubscriptionsTheStoreDoesNotHold() {
        let drift = SubscriptionGroupDrift.compare(
            local: ProductCatalog(
                products: ["com.example.monthly": subscription()],
                groups: ["Premium": premium()]
            ),
            remote: remote(products: [:])
        )
        #expect(drift.agrees)
    }

    @Test func leavesAGroupSomebodySplit() {
        let drift = SubscriptionGroupDrift.compare(
            local: ProductCatalog(products: [
                "com.example.monthly": subscription(),
                "com.example.yearly": subscription(id: "com.example.yearly")
            ]),
            remote: remote(
                groups: [
                    RemoteSubscriptionGroup(id: "g1", referenceName: "Plus"),
                    RemoteSubscriptionGroup(id: "g2", referenceName: "Max")
                ],
                products: ["com.example.monthly": "Plus", "com.example.yearly": "Max"]
            )
        )
        #expect(drift.agrees)
    }

    // MARK: - Following

    @Test func keepsTheWordsAndTheStatusOfARenamedGroup() throws {
        try fixture.writeProduct(subscription())
        try fixture.writeGroup(premium())

        let followed = try follow(remote())
        let catalog = try fixture.products()

        #expect(followed.renamed.map(\.to) == ["Plus"])
        #expect(followed.trashed.isEmpty)
        #expect(Array(catalog.groups.keys) == ["Plus"])
        #expect(catalog.groups["Plus"]?.status == .approved)
        #expect(catalog.groups["Plus"]?.localizations == premium().localizations)
        #expect(catalog.products["com.example.monthly"]?.subscriptionGroup == "Plus")
        #expect(catalog.products["com.example.monthly"]?.status == .approved)
    }

    @Test func unblocksThePlan() throws {
        try fixture.writeProduct(subscription())
        try fixture.writeGroup(premium())
        _ = try follow(remote())

        let outcome = try ProductPlanner.plan(local: fixture.products(), config: config, remote: remote())

        #expect(outcome.blocked.isEmpty)
        #expect(outcome.groupTextChanges.map(\.group) == ["Plus", "Plus"])
    }

    @Test func followsARenameThatChangesOnlyTheCase() throws {
        try fixture.writeProduct(subscription())
        try fixture.writeGroup(premium())

        _ = try follow(remote(
            groups: [RemoteSubscriptionGroup(id: "g1", referenceName: "premium")],
            products: ["com.example.monthly": "premium"]
        ))

        let catalog = try fixture.products()
        #expect(Array(catalog.groups.keys) == ["premium"])
        #expect(catalog.groups["premium"]?.localizations == premium().localizations)
    }

    @Test func trashesAGroupWithNoSubscriptionAndShowsWhatTheStoreHolds() throws {
        try fixture.writeGroup(premium())

        let followed = try follow(remote(
            groups: [
                RemoteSubscriptionGroup(id: "g1", referenceName: "Plus", localizations: [
                    "en-US": RemoteGroupLocalization(id: "l1", locale: "en-US", name: "Plus")
                ]),
                RemoteSubscriptionGroup(id: "g2", referenceName: "Empty")
            ],
            products: [:]
        ))
        let catalog = try fixture.products()

        #expect(followed.trashed == ["Premium"])
        #expect(followed.written == ["Plus", "Empty"])
        #expect(catalog.groups.keys.sorted() == ["Empty", "Plus"])
        #expect(catalog.groups["Plus"]?.status == .needsHuman)
        #expect(catalog.groups["Plus"]?.localizations["en-US"]?.name == "Plus")
    }

    /// A pull before the rename was followed writes the new name beside the
    /// old one.
    @Test func putsThePersonsFileInPlaceOfACopyOfTheStore() throws {
        let held = RemoteSubscriptionGroup(id: "g1", referenceName: "Plus", localizations: [
            "en-US": RemoteGroupLocalization(id: "l1", locale: "en-US", name: "Old words")
        ])
        try fixture.writeProduct(subscription())
        try fixture.writeGroup(premium())
        try fixture.writeGroup(ProductSnapshot.make(held, config: config))

        let followed = try follow(remote(groups: [held]))
        let catalog = try fixture.products()

        #expect(followed.trashed.isEmpty)
        #expect(Array(catalog.groups.keys) == ["Plus"])
        #expect(catalog.groups["Plus"]?.status == .approved)
        #expect(catalog.groups["Plus"]?.localizations == premium().localizations)
    }

    @Test func keepsAFileAPersonWroteUnderTheNewName() throws {
        let written = SubscriptionGroup(
            referenceName: "Plus",
            status: .approved,
            localizations: ["en-US": .init(name: "Plus, by hand")]
        )
        try fixture.writeProduct(subscription())
        try fixture.writeGroup(premium())
        try fixture.writeGroup(written)

        let followed = try follow(remote())
        let catalog = try fixture.products()

        #expect(followed.trashed == ["Premium"])
        #expect(catalog.groups == ["Plus": written])
        #expect(catalog.products["com.example.monthly"]?.subscriptionGroup == "Plus")
    }

    // MARK: - Saying it

    @Test func saysWhatMovedAndWhatWentToTheTrash() {
        let text = PushOutcomeText.describe(SubscriptionGroupDrift.Followed(
            renamed: [.init(from: "Premium", to: "Plus", productIDs: [])],
            trashed: ["Old"],
            written: ["New"]
        ))

        #expect(text.contains("  groups/Premium is now groups/Plus"))
        #expect(text.contains("  groups/Old"))
        #expect(text.contains("  groups/New"))
    }
}
