import ASCKitTestSupport
import Foundation
import Testing
@testable import ASCKitAPI

/// A price write, checked at the level of the JSON that leaves the machine.
///
/// This is the one place in the feature where a mistake is silent. A wrong
/// relationship key or a local id that does not match is not a bad price, it is
/// a refusal or a schedule that means something else, and neither reads as
/// wrong from inside.
struct PriceWriteTests {
    func body(of request: URLRequest) throws -> [String: Any] {
        let data = try #require(request.httpBody)
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func data(of request: URLRequest) throws -> [String: Any] {
        try #require(try body(of: request)["data"] as? [String: Any])
    }

    func relationships(of request: URLRequest) throws -> [String: Any] {
        try #require(try data(of: request)["relationships"] as? [String: Any])
    }

    /// The id inside a to-one relationship, which is where every mistake here
    /// would show up.
    func relatedID(_ name: String, in request: URLRequest) throws -> String {
        let holder = try #require(try relationships(of: request)[name] as? [String: Any])
        let identifier = try #require(holder["data"] as? [String: Any])
        return try #require(identifier["id"] as? String)
    }

    // MARK: - A one-time purchase

    func scheduleRequest(
        prices: [PriceWrite] = [
            PriceWrite(territory: "USA", pricePointID: "point-usa"),
            PriceWrite(territory: "DEU", pricePointID: "point-deu")
        ]
    ) async throws -> URLRequest {
        let transport = StubTransport(.ok(#"{"data":{"type":"inAppPurchasePriceSchedules","id":"s1"}}"#))
        let client = try ASCClient.stubbed(transport: transport)
        try await client.createPriceSchedule(
            purchaseID: "p1",
            baseTerritory: "USA",
            prices: prices
        )
        return await transport.request(at: 0)
    }

    @Test func sendsAScheduleToTheRightPlace() async throws {
        let request = try await scheduleRequest()
        #expect(request.url?.path == "/v1/inAppPurchasePriceSchedules")
        #expect(request.httpMethod == "POST")
        #expect(try data(of: request)["type"] as? String == "inAppPurchasePriceSchedules")
    }

    /// Apple's own worked example leaves this out, and it is required.
    @Test func namesTheBaseTerritoryEveryTime() async throws {
        #expect(try await relatedID("baseTerritory", in: scheduleRequest()) == "USA")
    }

    @Test func pointsTheScheduleAtTheProduct() async throws {
        #expect(try await relatedID("inAppPurchase", in: scheduleRequest()) == "p1")
    }

    /// The prices do not exist yet, so `manualPrices` points at local ids and
    /// the objects themselves travel in `included`. An id in one that is not in
    /// the other is a request App Store Connect cannot make sense of.
    @Test func matchesEveryLocalIdInManualPricesToOneInIncluded() async throws {
        let request = try await scheduleRequest()

        let manual = try #require(relationships(of: request)["manualPrices"] as? [String: Any])
        let pointedAt = try #require(manual["data"] as? [[String: Any]])
        let wanted = Set(pointedAt.compactMap { $0["id"] as? String })

        let included = try #require(body(of: request)["included"] as? [[String: Any]])
        let defined = Set(included.compactMap { $0["id"] as? String })

        #expect(wanted == defined)
        #expect(wanted == ["${price-USA}", "${price-DEU}"])
    }

    @Test func givesEveryIncludedPriceItsCountryAndItsPricePoint() async throws {
        let request = try await scheduleRequest()
        let included = try #require(body(of: request)["included"] as? [[String: Any]])

        let usa = try #require(included.first { $0["id"] as? String == "${price-USA}" })
        #expect(usa["type"] as? String == "inAppPurchasePrices")

        let related = try #require(usa["relationships"] as? [String: Any])
        for (name, expected) in [
            ("territory", "USA"),
            ("inAppPurchasePricePoint", "point-usa"),
            ("inAppPurchaseV2", "p1")
        ] {
            let holder = try #require(related[name] as? [String: Any])
            let identifier = try #require(holder["data"] as? [String: Any])
            #expect(identifier["id"] as? String == expected, "\(name) is wrong")
        }
    }

    /// Null is a real value here. It says the price starts as soon as the write
    /// lands, and leaving the key out entirely is a different thing.
    @Test func sendsANullStartDateRatherThanLeavingItOut() async throws {
        let request = try await scheduleRequest()
        let included = try #require(body(of: request)["included"] as? [[String: Any]])
        let usa = try #require(included.first { $0["id"] as? String == "${price-USA}" })
        let attributes = try #require(usa["attributes"] as? [String: Any])

        #expect(attributes.keys.contains("startDate"))
        #expect(attributes["startDate"] is NSNull)
    }

    @Test func sendsAStartDateWhenOneIsGiven() async throws {
        let request = try await scheduleRequest(prices: [
            PriceWrite(territory: "USA", pricePointID: "point-usa", startDate: "2027-01-01")
        ])
        let included = try #require(body(of: request)["included"] as? [[String: Any]])
        let attributes = try #require(included[0]["attributes"] as? [String: Any])
        #expect(attributes["startDate"] as? String == "2027-01-01")
    }

    /// One request, whatever the number of countries. A schedule replaces the
    /// one before it, so splitting it across requests would leave every country
    /// but the last back on Apple's own price.
    @Test func sendsEveryCountryInOneRequest() async throws {
        let many = (1 ... 60).map {
            PriceWrite(territory: "T\($0)", pricePointID: "point-\($0)")
        }
        let transport = StubTransport(.ok(#"{"data":{"type":"inAppPurchasePriceSchedules","id":"s1"}}"#))
        let client = try ASCClient.stubbed(transport: transport)
        try await client.createPriceSchedule(
            purchaseID: "p1", baseTerritory: "T1", prices: many
        )

        #expect(await transport.requestCount == 1)
        let included = try await #require(body(of: transport.request(at: 0))["included"] as? [[String: Any]])
        #expect(included.count == 60)
    }

    // MARK: - A subscription, every country at once

    func everyCountryRequest(
        prices: [PriceWrite] = [
            PriceWrite(territory: "USA", pricePointID: "point-usa"),
            PriceWrite(territory: "DEU", pricePointID: "point-deu")
        ],
        preserving: Bool = true
    ) async throws -> URLRequest {
        let transport = StubTransport(.ok(#"{"data":{"type":"subscriptions","id":"s1"}}"#))
        let client = try ASCClient.stubbed(transport: transport)
        try await client.updateSubscriptionPrices(
            subscriptionID: "s1",
            prices: prices,
            preserveCurrentPrice: preserving
        )
        return await transport.request(at: 0)
    }

    /// A subscription has no price schedule, but it takes a compound update
    /// that carries every country in one go.
    @Test func changesTheSubscriptionItselfRatherThanPostingEachPrice() async throws {
        let request = try await everyCountryRequest()
        #expect(request.url?.path == "/v1/subscriptions/s1")
        #expect(request.httpMethod == "PATCH")
        #expect(try data(of: request)["type"] as? String == "subscriptions")
        #expect(try data(of: request)["id"] as? String == "s1")
    }

    @Test func matchesEveryLocalIdInPricesToOneInIncluded() async throws {
        let request = try await everyCountryRequest()

        let prices = try #require(relationships(of: request)["prices"] as? [String: Any])
        let pointedAt = try #require(prices["data"] as? [[String: Any]])
        let wanted = Set(pointedAt.compactMap { $0["id"] as? String })

        let included = try #require(body(of: request)["included"] as? [[String: Any]])
        let defined = Set(included.compactMap { $0["id"] as? String })

        #expect(wanted == defined)
        // The plan type is part of the local id, because a country sends two
        // prices and one id cannot stand for both.
        #expect(wanted == ["${price-USA-UPFRONT}", "${price-DEU-UPFRONT}"])
    }

    /// A country on a 12-month commitment sends the year and one month of it,
    /// and both have to survive the round trip into `included`.
    @Test func sendsBothPlanTypesForOneCountry() async throws {
        let request = try await everyCountryRequest(prices: [
            PriceWrite(territory: "DEU", pricePointID: "point-year", planType: "UPFRONT"),
            PriceWrite(territory: "DEU", pricePointID: "point-month", planType: "MONTHLY")
        ])

        let included = try #require(body(of: request)["included"] as? [[String: Any]])
        #expect(included.count == 2)

        let ids = Set(included.compactMap { $0["id"] as? String })
        #expect(ids == ["${price-DEU-UPFRONT}", "${price-DEU-MONTHLY}"])

        let month = try #require(included.first { $0["id"] as? String == "${price-DEU-MONTHLY}" })
        let attributes = try #require(month["attributes"] as? [String: Any])
        #expect(attributes["planType"] as? String == "MONTHLY")
    }

    @Test func givesEveryIncludedSubscriptionPriceItsCountryPointAndPlanType() async throws {
        let request = try await everyCountryRequest()
        let included = try #require(body(of: request)["included"] as? [[String: Any]])
        let usa = try #require(included.first { $0["id"] as? String == "${price-USA-UPFRONT}" })

        #expect(usa["type"] as? String == "subscriptionPrices")

        let attributes = try #require(usa["attributes"] as? [String: Any])
        #expect(attributes["planType"] as? String == "UPFRONT")
        #expect(attributes["preserveCurrentPrice"] as? Bool == true)
        #expect(attributes["startDate"] is NSNull)

        let related = try #require(usa["relationships"] as? [String: Any])
        for (name, expected) in [
            ("territory", "USA"),
            ("subscriptionPricePoint", "point-usa"),
            ("subscription", "s1")
        ] {
            let holder = try #require(related[name] as? [String: Any])
            let identifier = try #require(holder["data"] as? [String: Any])
            #expect(identifier["id"] as? String == expected, "\(name) is wrong")
        }
    }

    /// One request whatever the number of countries. That is the whole point of
    /// this path, and it is also what makes the replace-or-merge question moot,
    /// because everything is in the body either way.
    @Test func sendsEveryCountryOfASubscriptionInOneRequest() async throws {
        let many = (1 ... 170).map {
            PriceWrite(territory: "T\($0)", pricePointID: "point-\($0)")
        }
        let transport = StubTransport(.ok(#"{"data":{"type":"subscriptions","id":"s1"}}"#))
        let client = try ASCClient.stubbed(transport: transport)
        try await client.updateSubscriptionPrices(
            subscriptionID: "s1", prices: many, preserveCurrentPrice: true
        )

        #expect(await transport.requestCount == 1)
        let included = try await #require(
            body(of: transport.request(at: 0))["included"] as? [[String: Any]]
        )
        #expect(included.count == 170)
    }

    @Test func showsExactlyTheBodyAnEveryCountryWriteWouldSend() async throws {
        let prices = [PriceWrite(territory: "USA", pricePointID: "point-usa")]
        let shown = PriceWritePreview.subscriptionPrices(
            subscriptionID: "s1", prices: prices, preserveCurrentPrice: true
        )

        let sent = try await everyCountryRequest(prices: prices)
        let one = try JSONSerialization.jsonObject(with: #require(sent.httpBody)) as? NSDictionary
        let other = try JSONSerialization.jsonObject(
            with: #require(shown.data(using: .utf8))
        ) as? NSDictionary
        #expect(one == other)
    }

    // MARK: - A subscription, one country at a time

    func subscriptionRequest(preserving: Bool = true) async throws -> URLRequest {
        let transport = StubTransport(.ok(#"{"data":{"type":"subscriptionPrices","id":"x1"}}"#))
        let client = try ASCClient.stubbed(transport: transport)
        try await client.createSubscriptionPrice(
            subscriptionID: "s1",
            price: PriceWrite(territory: "DEU", pricePointID: "point-deu"),
            preserveCurrentPrice: preserving
        )
        return await transport.request(at: 0)
    }

    @Test func sendsOneSubscriptionPriceToTheRightPlace() async throws {
        let request = try await subscriptionRequest()
        #expect(request.url?.path == "/v1/subscriptionPrices")
        #expect(try data(of: request)["type"] as? String == "subscriptionPrices")
    }

    @Test func pointsASubscriptionPriceAtItsCountryAndItsPoint() async throws {
        let request = try await subscriptionRequest()
        #expect(try relatedID("subscription", in: request) == "s1")
        #expect(try relatedID("territory", in: request) == "DEU")
        #expect(try relatedID("subscriptionPricePoint", in: request) == "point-deu")
    }

    /// The flag that decides whether people who already pay keep their price.
    /// Getting it wrong on a rise puts every one of them into Apple's consent
    /// flow, and the ones who do not answer are cancelled.
    @Test(arguments: [true, false])
    func sendsWhetherExistingSubscribersAreProtected(preserving: Bool) async throws {
        let request = try await subscriptionRequest(preserving: preserving)
        let attributes = try #require(data(of: request)["attributes"] as? [String: Any])
        #expect(attributes["preserveCurrentPrice"] as? Bool == preserving)
    }

    // MARK: - What a dry run shows

    /// A dry run that printed something a real run would not send would be
    /// worse than no dry run at all.
    @Test func showsExactlyTheBodyAScheduleWriteWouldSend() async throws {
        let prices = [PriceWrite(territory: "USA", pricePointID: "point-usa")]
        let shown = PriceWritePreview.priceSchedule(
            purchaseID: "p1", baseTerritory: "USA", prices: prices
        )

        let sent = try await scheduleRequest(prices: prices)
        let sentJSON = try #require(sent.httpBody)
        let shownJSON = try #require(shown.data(using: .utf8))

        let one = try JSONSerialization.jsonObject(with: sentJSON) as? NSDictionary
        let other = try JSONSerialization.jsonObject(with: shownJSON) as? NSDictionary
        #expect(one == other)
    }

    @Test func showsExactlyTheBodyASubscriptionPriceWouldSend() async throws {
        let shown = PriceWritePreview.subscriptionPrice(
            subscriptionID: "s1",
            price: PriceWrite(territory: "DEU", pricePointID: "point-deu"),
            preserveCurrentPrice: true
        )

        let sent = try await subscriptionRequest()
        let one = try JSONSerialization.jsonObject(with: #require(sent.httpBody)) as? NSDictionary
        let other = try JSONSerialization.jsonObject(
            with: #require(shown.data(using: .utf8))
        ) as? NSDictionary
        #expect(one == other)
    }
}
