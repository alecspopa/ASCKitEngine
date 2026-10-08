import Foundation
import Testing
@testable import ASCKitProject

final class ProductStoreTests {
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

    func subscription(
        id: String = "com.example.pro.monthly",
        status: AppInformation.Status = .draft
    ) -> Product {
        Product(
            productID: id,
            kind: Product.Kind.autoRenewableSubscription.rawValue,
            subscriptionGroup: "Pro",
            subscriptionPeriod: "ONE_MONTH",
            status: status,
            price: Product.PricePlan(
                baseTerritory: "USA",
                baseAmount: Money("4.99"),
                curve: "purchasing-power"
            ),
            localizations: [
                "en-US": .init(name: "Pro Monthly", description: "Everything in Pro, monthly."),
                "de-DE": .init(name: "Pro Monatlich", description: "Alles in Pro, monatlich.")
            ]
        )
    }

    // MARK: - Reading

    @Test func readsNothingFromAProjectWithNoProductsFolder() throws {
        let catalog = try fixture.products()
        #expect(catalog.isEmpty)
        #expect(catalog.products.isEmpty)
    }

    @Test func readsAProductBack() throws {
        try fixture.writeProduct(subscription())
        let catalog = try fixture.products()
        let product = catalog.products["com.example.pro.monthly"]
        #expect(product?.resolvedKind == .autoRenewableSubscription)
        #expect(product?.subscriptionGroup == "Pro")
        #expect(product?.price?.baseAmount.description == "4.99")
        #expect(product?.localizations["de-DE"]?.name == "Pro Monatlich")
    }

    /// The file name holds dots, and so does every product id anybody writes.
    @Test func readsAFileWhoseNameHoldsDots() throws {
        try fixture.writeProduct(subscription(id: "com.example.a.b.c.d"))
        #expect(try fixture.products().products["com.example.a.b.c.d"] != nil)
    }

    /// One broken file must not stop a window opening on the rest.
    @Test func keepsReadingAfterAFileItCannotUnderstand() throws {
        try fixture.writeProduct(subscription())
        try fixture.writeRawProduct("{ not json", named: "com.example.broken.json")

        let catalog = try fixture.products()
        #expect(catalog.products.count == 1)
        #expect(catalog.unreadable["com.example.broken"] != nil)
    }

    @Test func refusesAnAmountWrittenAsANumberRatherThanAString() throws {
        try fixture.writeRawProduct(
            """
            { "productId": "com.example.tip", "kind": "consumable",
              "price": { "baseTerritory": "USA", "baseAmount": 4.99, "curve": "apple-equalized" } }
            """,
            named: "com.example.tip.json"
        )
        #expect(try fixture.products().unreadable["com.example.tip"] != nil)
    }

    /// The file name is what a person reads and what ASCKit files by, so it
    /// wins. The disagreement is reported rather than followed.
    @Test func takesTheFileNameOverTheProductIdInsideTheFile() throws {
        try fixture.writeProduct(subscription(id: "com.example.wrong"),
                                 named: "com.example.right.json")

        let catalog = try fixture.products()
        #expect(catalog.products["com.example.right"]?.productID == "com.example.right")
        #expect(catalog.misnamed["com.example.right"] == "com.example.wrong")
    }

    /// The silence file sits with the products it is about, so the reader has
    /// to know it is not one of them.
    @Test func doesNotReadTheSilenceFileAsAProduct() throws {
        try fixture.writeProduct(subscription())
        try fixture.writeRawProduct(#"{"warnings": []}"#, named: "silenced.json")

        let catalog = try fixture.products()
        #expect(catalog.products.count == 1)
        #expect(catalog.unreadable.isEmpty)
    }

    // MARK: - Writing

    @Test func writesAProductAndReadsItBackUnchanged() throws {
        let project = try fixture.load()
        try ContentWriter.writeProduct(subscription(status: .approved), in: project)

        let read = ProductStore.load(in: project).products["com.example.pro.monthly"]
        #expect(read == subscription(status: .approved))
    }

    @Test func refusesAProductCalledSilenced() throws {
        let project = try fixture.load()
        #expect(throws: ContentWriteError.self) {
            try ContentWriter.writeProduct(
                Product(productID: "silenced", kind: "consumable"),
                in: project
            )
        }
    }

    @Test(arguments: ["", "a/b", ".hidden"])
    func refusesAProductIdThatCannotBeAFileName(productID: String) {
        #expect(ProductStore.reasonToRefuse(productID: productID) != nil)
    }

    @Test func acceptsAnOrdinaryProductId() {
        #expect(ProductStore.reasonToRefuse(productID: "com.example.pro.monthly") == nil)
    }
}
