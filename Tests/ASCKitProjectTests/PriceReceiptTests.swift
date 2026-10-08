import Foundation
import Testing
@testable import ASCKitProject

/// The receipt is the audit trail for a change that moves real money. It is the
/// most important file this feature writes.
final class PriceReceiptTests {
    let fixture: FixtureProject

    init() throws {
        fixture = try FixtureProject()
        _ = try fixture.writeConfig(ProjectConfig(bundleID: "com.example.MyApp", keyID: "ABC"))
    }

    deinit {
        fixture.remove()
    }

    func written(
        _ territory: String,
        from: String? = "1.99",
        to: String = "2.99",
        preserved: Bool? = true
    ) -> ProductPusher.Written {
        ProductPusher.Written(
            productID: "com.example.pro",
            territory: territory,
            planType: "UPFRONT",
            currency: "USD",
            from: from,
            to: to,
            pricePointID: "point-\(territory)",
            preservedCurrentPrice: preserved
        )
    }

    func result(
        written: [ProductPusher.Written] = [],
        failed: [ProductPusher.Failure] = []
    ) -> ProductPusher.PriceResult {
        var result = ProductPusher.PriceResult()
        result.written = written
        result.failed = failed
        return result
    }

    // MARK: - What a price receipt keeps

    @Test func recordsWhatEachCountryPaidBeforeAndAfter() throws {
        let receipt = PushReceipt.forPrices(
            result(written: [written("USA"), written("DEU", from: nil, to: "3.99")]),
            at: Date(timeIntervalSince1970: 0)
        )

        let usa = try #require(receipt.prices?.first { $0.territory == "USA" })
        #expect(usa.from == "1.99")
        #expect(usa.to == "2.99")
        #expect(usa.currency == "USD")

        // A country the store charged nothing for yet has no before.
        let deu = try #require(receipt.prices?.first { $0.territory == "DEU" })
        #expect(deu.from == nil)
    }

    /// Apple regenerates price point ids, so the one that was written is worth
    /// keeping for anybody reading this back later.
    @Test func recordsThePricePointThatWasActuallyWritten() {
        let receipt = PushReceipt.forPrices(
            result(written: [written("USA")]), at: Date(timeIntervalSince1970: 0)
        )
        #expect(receipt.prices?.first?.pricePointID == "point-USA")
    }

    @Test func recordsWhetherExistingSubscribersWereProtected() {
        let receipt = PushReceipt.forPrices(
            result(written: [written("USA", preserved: false)]),
            at: Date(timeIntervalSince1970: 0)
        )
        #expect(receipt.prices?.first?.preservedCurrentPrice == false)
    }

    @Test func recordsEveryCountryThatFailedSoTheyCanBeTriedAgain() {
        let receipt = PushReceipt.forPrices(
            result(failed: [
                .init(productID: "com.example.pro", what: "IND", reason: "Not allowed here.")
            ]),
            at: Date(timeIntervalSince1970: 0)
        )
        #expect(receipt.failed.first?.locale == "com.example.pro IND")
        #expect(receipt.isCompleteSuccess == false)
    }

    // MARK: - Where it goes

    /// An in-app purchase belongs to no release, so the slot the version fills
    /// says what the push was about instead.
    @Test func namesAPriceReceiptAfterTheProductsRatherThanAVersion() {
        let receipt = PushReceipt.forPrices(result(), at: Date(timeIntervalSince1970: 0))
        #expect(receipt.version == nil)
        #expect(PushHistory.fileName(for: receipt).contains("-products-prices.json"))
    }

    @Test func keepsAPriceReceiptWithTheRest() throws {
        let project = try fixture.load()
        try PushHistory.write(
            PushReceipt.forPrices(
                result(written: [written("USA")]), at: Date(timeIntervalSince1970: 0)
            ),
            to: project
        )

        let read = try #require(PushHistory.read(from: project).first)
        #expect(read.kind == .prices)
        #expect(read.prices?.first?.territory == "USA")
    }

    // MARK: - Older receipts

    /// A receipt written before in-app purchases existed has no prices key and
    /// a version that is always there. Both still read.
    @Test func readsAReceiptWrittenBeforeThisFeatureExisted() throws {
        let old = """
        {"appVersionState":"PREPARE_FOR_SUBMISSION","failed":[],"kind":"text",
         "pushedAt":"1970-01-01T00:00:00Z","refused":[],"version":"1.0",
         "written":["en-US"]}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let receipt = try decoder.decode(PushReceipt.self, from: Data(old.utf8))
        #expect(receipt.version == "1.0")
        #expect(receipt.kind == .text)
        #expect(receipt.prices == nil)
        #expect(PushHistory.fileName(for: receipt).contains("-1.0-text.json"))
    }

    // MARK: - Words

    @Test func recordsWhichLanguagesOfWhichProductWent() {
        let result = ProductPusher.TextResult(
            written: ["com.example.pro en-US"],
            failed: [.init(productID: "com.example.pro", what: "de-DE", reason: "No.")]
        )
        let receipt = PushReceipt.forProductText(result, at: Date(timeIntervalSince1970: 0))

        #expect(receipt.kind == .productText)
        #expect(receipt.version == nil)
        #expect(receipt.written == ["com.example.pro en-US"])
        #expect(receipt.failed.first?.locale == "com.example.pro de-DE")
        #expect(receipt.prices == nil)
    }
}
