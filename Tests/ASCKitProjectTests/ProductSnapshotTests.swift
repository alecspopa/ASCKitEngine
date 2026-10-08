import ASCKitAPI
import Foundation
import Testing
@testable import ASCKitProject

final class ProductSnapshotTests {
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

    func remote(
        productID: String = "com.example.pro.monthly",
        kind: String = "auto_renewable_subscription",
        localizations: [String: RemoteProductLocalization]? = nil
    ) -> RemoteProducts {
        RemoteProducts(
            appID: "a1",
            products: [RemoteProduct(
                id: "s1",
                productID: productID,
                kind: kind,
                referenceName: "Pro Monthly",
                state: "APPROVED",
                reviewNote: "Sign in with the demo account.",
                familySharable: true,
                subscriptionGroup: "Pro",
                subscriptionPeriod: "ONE_MONTH",
                localizations: localizations ?? [
                    "en-US": .init(id: "l1", locale: "en-US", name: "Pro Monthly",
                                   description: "Everything in Pro."),
                    "de-DE": .init(id: "l2", locale: "de-DE", name: "Pro Monatlich",
                                   description: "Alles in Pro.")
                ]
            )],
            groupNames: ["g1": "Pro"]
        )
    }

    // MARK: - What a pulled file says

    @Test func writesAProductFileFromWhatTheStoreHolds() throws {
        let project = try fixture.load()
        let outcome = try ProductSnapshot.write(remote(), to: project)

        #expect(outcome.written == ["com.example.pro.monthly"])
        let read = ProductStore.load(in: project).products["com.example.pro.monthly"]
        #expect(read?.resolvedKind == .autoRenewableSubscription)
        #expect(read?.subscriptionGroup == "Pro")
        #expect(read?.subscriptionPeriod == "ONE_MONTH")
        #expect(read?.reviewNote == "Sign in with the demo account.")
        #expect(read?.localizations["de-DE"]?.name == "Pro Monatlich")
    }

    /// A file that arrives by itself saying approved is a file that gets
    /// published without anybody reading it.
    @Test func marksAPulledProductAsNeedingAPerson() throws {
        let project = try fixture.load()
        _ = try ProductSnapshot.write(remote(), to: project)
        let read = ProductStore.load(in: project).products["com.example.pro.monthly"]
        #expect(read?.status == .needsHuman)
        #expect(read?.status.canPublish == false)
    }

    /// Reading what a product costs everywhere means reading thousands of price
    /// points, so a pull does not guess at a plan.
    @Test func leavesAPulledProductWithNoPricePlan() throws {
        let project = try fixture.load()
        _ = try ProductSnapshot.write(remote(), to: project)
        #expect(ProductStore.load(in: project).products["com.example.pro.monthly"]?.price == nil)
    }

    @Test func leavesOutALanguageTheProjectDoesNotShip() throws {
        let project = try fixture.load()
        _ = try ProductSnapshot.write(remote(localizations: [
            "en-US": .init(id: "l1", locale: "en-US", name: "Pro", description: "All."),
            "fr-FR": .init(id: "l3", locale: "fr-FR", name: "Pro", description: "Tout.")
        ]), to: project)

        let read = ProductStore.load(in: project).products["com.example.pro.monthly"]
        #expect(read?.localizations.keys.sorted() == ["en-US"])
    }

    @Test func namesTheLanguagesTheStoreHasAndTheProjectDoesNot() throws {
        let project = try fixture.load()
        let unshipped = ProductSnapshot.unshippedLocales(
            in: remote(localizations: [
                "en-US": .init(id: "l1", locale: "en-US", name: "Pro", description: "All."),
                "fr-FR": .init(id: "l3", locale: "fr-FR", name: "Pro", description: "Tout."),
                "ja": .init(id: "l4", locale: "ja", name: "Pro", description: "すべて。")
            ]),
            config: project.config
        )
        #expect(unshipped == ["fr-FR", "ja"])
    }

    // MARK: - Not writing over somebody's work

    /// What is on disk may be a translation somebody is still working on.
    @Test func leavesAFileThatIsAlreadyThere() throws {
        let project = try fixture.load()
        try fixture.writeProduct(Product(
            productID: "com.example.pro.monthly",
            kind: "auto_renewable_subscription",
            status: .approved,
            localizations: ["en-US": .init(name: "Mine", description: "My words.")]
        ))

        let outcome = try ProductSnapshot.write(remote(), to: project)
        #expect(outcome.written.isEmpty)
        #expect(outcome.left == ["com.example.pro.monthly"])

        let read = ProductStore.load(in: project).products["com.example.pro.monthly"]
        #expect(read?.localizations["en-US"]?.name == "Mine")
        #expect(read?.status == .approved)
    }

    @Test func writesOverAFileWhenToldTo() throws {
        let project = try fixture.load()
        try fixture.writeProduct(Product(
            productID: "com.example.pro.monthly",
            kind: "auto_renewable_subscription",
            status: .approved,
            localizations: ["en-US": .init(name: "Mine", description: "My words.")]
        ))

        let outcome = try ProductSnapshot.write(remote(), to: project, overwrite: true)
        #expect(outcome.written == ["com.example.pro.monthly"])
        let read = ProductStore.load(in: project).products["com.example.pro.monthly"]
        #expect(read?.localizations["en-US"]?.name == "Pro Monthly")
    }

    @Test func skipsAProductWhoseIdCannotBeAFileName() throws {
        let project = try fixture.load()
        let outcome = try ProductSnapshot.write(remote(productID: "silenced"), to: project)
        #expect(outcome.written.isEmpty)
        #expect(outcome.refused.first?.productID == "silenced")
    }
}
