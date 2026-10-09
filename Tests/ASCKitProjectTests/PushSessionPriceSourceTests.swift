import ASCKitAPI
import ASCKitTestSupport
import Foundation
import Testing
@testable import ASCKitProject

/// Where a read gets its price ladders, and what it costs.
///
/// A ladder is the slowest thing ASCKit does, so a project keeps one. What
/// these check is that keeping it changes what is asked for and changes nothing
/// about the answer: a plan built off a kept ladder has to be a plan a push can
/// write.
final class PushSessionPriceSourceTests {
    let fixture: FixtureProject

    init() throws {
        fixture = try FixtureProject()
        _ = try fixture.writeConfig(ProjectConfig(
            bundleID: "com.example.Demo",
            keyID: "ABC123",
            sourceLocale: "en-US",
            locales: ["en-US"]
        ))
        try fixture.writeProduct(Self.subscription)
    }

    deinit {
        fixture.remove()
    }

    static let subscription = Product(
        productID: "com.example.pro",
        kind: Product.Kind.autoRenewableSubscription.rawValue,
        subscriptionGroup: "Pro",
        subscriptionPeriod: "ONE_MONTH",
        status: .approved,
        price: Product.PricePlan(
            baseTerritory: "USA",
            baseAmount: Money(string: "4.99")!,
            curve: PriceCurve.appleEqualized.id
        )
    )

    /// A second subscription in the same group, which this project holds a
    /// file for and gives no price. What most products look like before
    /// somebody prices them.
    static let unpriced = Product(
        productID: "com.example.plus",
        kind: Product.Kind.autoRenewableSubscription.rawValue,
        subscriptionGroup: "Pro",
        subscriptionPeriod: "ONE_YEAR",
        status: .approved
    )

    // MARK: - A recorded App Store Connect

    /// Every country ASCKit knows, at two prices each, because a kept ladder is
    /// unusable unless it covers all of them.
    static let pricePointsJSON: String = {
        let rows = Territory.allIdentifiers.flatMap { territory in
            ["399", "499"].map { step in
                """
                {"type":"subscriptionPricePoints","id":"\(territory)-\(step)",
                 "attributes":{"customerPrice":"\(step.prefix(1)).\(step.suffix(2))"},
                 "relationships":{"territory":{"data":{"type":"territories","id":"\(territory)"}}}}
                """
            }
        }
        return "{\"data\":[\(rows.joined(separator: ","))]}"
    }()

    /// Apple never names the base country in its own equivalent prices, so this
    /// leaves the United States out.
    static let equalizationsJSON: String = {
        let rows = Territory.allIdentifiers.filter { $0 != "USA" }.map { territory in
            """
            {"type":"subscriptionPricePoints","id":"\(territory)-499",
             "attributes":{"customerPrice":"4.99"},
             "relationships":{"territory":{"data":{"type":"territories","id":"\(territory)"}}}}
            """
        }
        return "{\"data\":[\(rows.joined(separator: ","))]}"
    }()

    /// The United States pays 4.99 today and Germany pays 3.99, so Germany is
    /// the country that moves.
    static let currentPricesJSON = """
    {"data":[
      {"type":"subscriptionPrices","id":"p1","attributes":{"planType":"UPFRONT"},
       "relationships":{
         "territory":{"data":{"type":"territories","id":"USA"}},
         "subscriptionPricePoint":{"data":{"type":"subscriptionPricePoints","id":"USA-499"}}}},
      {"type":"subscriptionPrices","id":"p2","attributes":{"planType":"UPFRONT"},
       "relationships":{
         "territory":{"data":{"type":"territories","id":"DEU"}},
         "subscriptionPricePoint":{"data":{"type":"subscriptionPricePoints","id":"DEU-399"}}}}
    ],
    "included":[
      {"type":"subscriptionPricePoints","id":"USA-499","attributes":{"customerPrice":"4.99"}},
      {"type":"subscriptionPricePoints","id":"DEU-399","attributes":{"customerPrice":"3.99"}}
    ]}
    """

    /// The yearly subscription is sold outright and in monthly instalments in
    /// the United States. Apple sends one row for each.
    static let yearlyPricesJSON = """
    {"data":[
      {"type":"subscriptionPrices","id":"y1","attributes":{"planType":"UPFRONT"},
       "relationships":{
         "territory":{"data":{"type":"territories","id":"USA"}},
         "subscriptionPricePoint":{"data":{"type":"subscriptionPricePoints","id":"USA-499"}}}},
      {"type":"subscriptionPrices","id":"y2","attributes":{"planType":"MONTHLY"},
       "relationships":{
         "territory":{"data":{"type":"territories","id":"USA"}},
         "subscriptionPricePoint":{"data":{"type":"subscriptionPricePoints","id":"USA-049"}}}}
    ],
    "included":[
      {"type":"subscriptionPricePoints","id":"USA-499","attributes":{"customerPrice":"4.99"}},
      {"type":"subscriptionPricePoints","id":"USA-049","attributes":{"customerPrice":"0.49"}}
    ]}
    """

    /// - Parameters:
    ///   - ladderIDSuffix: Added to every price point id, so a second read can
    ///     hand back the same prices under identifiers Apple regenerated.
    ///   - pricePoints: The ladder itself, for a test about what Apple answers.
    ///   - withUnpriced: Whether the store holds `com.example.plus` as well.
    func transport(
        ladderIDSuffix: String = "",
        pricePoints: String? = nil,
        withUnpriced: Bool = false
    ) -> StubTransport {
        let ladder = (pricePoints ?? Self.pricePointsJSON).replacingOccurrences(
            of: "-499\"", with: "-499\(ladderIDSuffix)\""
        )
        let plus = """
        ,{"type":"subscriptions","id":"sub2","attributes":{
          "productId":"com.example.plus","name":"Plus",
          "subscriptionPeriod":"ONE_YEAR","state":"APPROVED"}}
        """
        return StubTransport(routes: StubTransport.emptyLibraryRoutes + [
            ("/subscriptions/sub1/pricePoints", .ok(ladder)),
            ("/equalizations", .ok(Self.equalizationsJSON)),
            ("/subscriptions/sub1/prices", .ok(Self.currentPricesJSON)),
            ("/subscriptions/sub2/prices", .ok(Self.yearlyPricesJSON)),
            ("/subscriptionGroups/group1/subscriptions", .ok("""
            {"data":[{"type":"subscriptions","id":"sub1","attributes":{
              "productId":"com.example.pro","name":"Pro",
              "subscriptionPeriod":"ONE_MONTH","state":"APPROVED"}}\(withUnpriced ? plus : "")]}
            """)),
            // These products hold no version, so nothing asks for their words.
            ("/subscriptions/sub1/versions", .ok(#"{"data":[]}"#)),
            ("/subscriptions/sub2/versions", .ok(#"{"data":[]}"#)),
            ("/subscriptionGroups/group1/versions", .ok(#"{"data":[]}"#)),
            ("/subscriptionGroups", .ok("""
            {"data":[{"type":"subscriptionGroups","id":"group1",
              "attributes":{"referenceName":"Pro"}}]}
            """)),
            ("/inAppPurchasesV2", .ok(#"{"data":[]}"#)),
            ("/appInfoLocalizations", .ok(#"{"data":[]}"#)),
            ("/appStoreVersionLocalizations", .ok(#"{"data":[]}"#)),
            ("/appInfos", .ok(#"{"data":[{"type":"appInfos","id":"info1","attributes":{}}]}"#)),
            ("/appScreenshotSets", .ok(#"{"data":[]}"#)),
            ("/appStoreVersions", .ok("""
            {"data":[{"type":"appStoreVersions","id":"v1","attributes":{
              "versionString":"1.0","appVersionState":"PREPARE_FOR_SUBMISSION"}}]}
            """)),
            ("/apps", .ok("""
            {"data":[{"type":"apps","id":"app1",
              "attributes":{"name":"Demo","bundleId":"com.example.Demo"}}]}
            """))
        ])
    }

    func session(on transport: StubTransport) throws -> PushSession {
        try PushSession(
            project: fixture.load(),
            client: ASCClient.stubbed(transport: transport)
        )
    }

    /// The requests that asked for a ladder, which is the expensive part.
    func ladderRequests(_ transport: StubTransport) async -> Int {
        await transport.requests
            .filter { $0.url?.path.hasSuffix("/pricePoints") == true }
            .count
    }

    func currentPriceRequests(_ transport: StubTransport) async -> Int {
        await transport.requests
            .filter { $0.url?.path.hasSuffix("/prices") == true }
            .count
    }

    // MARK: - What each source asks for

    /// A product this project does not price is still sold at a price, and the
    /// window shows it. That is one request and no ladder.
    @Test func readsTodaysPriceForAProductWithNoPricePlan() async throws {
        try fixture.writeProduct(Self.unpriced)
        let transport = transport(withUnpriced: true)
        let reading = try await session(on: transport).read(prices: .cached)

        #expect(reading.currentPrices["com.example.plus"]?["USA"] == Money(string: "4.99"))
        #expect(reading.priceOrigins["com.example.plus"] == nil)
        #expect(reading.changes?.pricePlans.contains { $0.productID == "com.example.plus" }
            == false)
    }

    /// The instalment comes back apart from the price of the whole year, so a
    /// window can show both for a product with no price plan.
    @Test func readsTodaysInstalmentForAProductWithNoPricePlan() async throws {
        try fixture.writeProduct(Self.unpriced)
        let transport = transport(withUnpriced: true)
        let reading = try await session(on: transport).read(prices: .cached)

        #expect(reading.currentPrices["com.example.plus"]?["USA"] == Money(string: "4.99"))
        #expect(reading.currentMonthlyPrices["com.example.plus"]?["USA"] == Money(string: "0.49"))
        #expect(reading.currentMonthlyPrices["com.example.pro"]?.isEmpty ?? true)
    }

    @Test func notReadAsksForNoPricesAtAll() async throws {
        let transport = transport()
        let reading = try await session(on: transport).read(prices: .notRead)

        #expect(await ladderRequests(transport) == 0)
        #expect(await currentPriceRequests(transport) == 0)
        #expect(reading.changes?.pricePlans.isEmpty == true)
        #expect(reading.priceOrigins.isEmpty)
    }

    @Test func freshReadsTheLadderAndKeepsIt() async throws {
        let transport = transport()
        let reading = try await session(on: transport).read(prices: .fresh)

        #expect(await ladderRequests(transport) > 0)
        #expect(reading.priceOrigins["com.example.pro"] == .network)
        #expect(try PriceLadderStore.load(productID: "com.example.pro", in: fixture.load()) != nil)
    }

    /// The whole point. A second read asks for no ladder, and still asks what
    /// each country pays today.
    @Test func cachedAsksForNoLadderAndStillAsksWhatIsChargedToday() async throws {
        try await session(on: transport()).read(prices: .fresh)

        let second = transport()
        let reading = try await session(on: second).read(prices: .cached)

        #expect(await ladderRequests(second) == 0)
        #expect(await currentPriceRequests(second) > 0)

        guard case let .cache(readOn) = reading.priceOrigins["com.example.pro"] else {
            Issue.record("The ladder did not come off the disk.")
            return
        }
        #expect(readOn == PriceLadderCache.today())
    }

    @Test func cachedFallsBackToTheNetworkWhenNothingIsKept() async throws {
        let transport = transport()
        let reading = try await session(on: transport).read(prices: .cached)

        #expect(await ladderRequests(transport) > 0)
        #expect(reading.priceOrigins["com.example.pro"] == .network)
    }

    /// Apple answered about 4.99. A plan asking about 3.99 needs its own
    /// answer, because every anchor was read for the old number.
    @Test func cachedFallsBackWhenTheBasePriceMoved() async throws {
        try await session(on: transport()).read(prices: .fresh)

        var moved = Self.subscription
        moved.price?.baseAmount = try #require(Money(string: "3.99"))
        try fixture.writeProduct(moved)

        let second = transport()
        let reading = try await session(on: second).read(prices: .cached)

        #expect(await ladderRequests(second) > 0)
        #expect(reading.priceOrigins["com.example.pro"] == .network)
    }

    /// Apple answers about the countries it sells the product in, which can be
    /// fewer than the hundred and seventy seven ASCKit asks about. A rule
    /// written against what came back rather than what was asked would throw
    /// every kept ladder away, and the cache would never be used at all.
    @Test func aLadderIsKeptEvenWhenAppleAnswersAboutFewerCountries() async throws {
        let twoCountries = """
        {"data":[
          {"type":"subscriptionPricePoints","id":"USA-499",
           "attributes":{"customerPrice":"4.99"},
           "relationships":{"territory":{"data":{"type":"territories","id":"USA"}}}},
          {"type":"subscriptionPricePoints","id":"DEU-499",
           "attributes":{"customerPrice":"4.99"},
           "relationships":{"territory":{"data":{"type":"territories","id":"DEU"}}}}
        ]}
        """
        try await session(on: transport(pricePoints: twoCountries)).read(prices: .fresh)

        let second = transport(pricePoints: twoCountries)
        let reading = try await session(on: second).read(prices: .cached)

        #expect(await ladderRequests(second) == 0)
        guard case .cache = reading.priceOrigins["com.example.pro"] else {
            Issue.record("A ladder Apple answered about two countries for was thrown away.")
            return
        }
    }

    // MARK: - The prices of one product

    /// The product on the store, as a read finds it.
    func remoteProduct(on transport: StubTransport) async throws -> RemoteProduct {
        let reading = try await session(on: transport).read(prices: .notRead)
        return try #require(reading.remoteProducts?.byProductID["com.example.pro"])
    }

    /// A preview works out every country and leaves the product file alone.
    @Test func aPreviewPricesAProductWithNoPlanAndWritesNothing() async throws {
        var unpriced = Self.subscription
        unpriced.price = nil
        try fixture.writeProduct(unpriced)

        let transport = transport()
        let match = try await remoteProduct(on: transport)
        let plan = try #require(Self.subscription.price)

        let preview = try await session(on: transport)
            .readProductPrices(of: unpriced, plan: plan, on: match)

        let change = try #require(preview.change)
        let germany = try #require(change.rows.first { $0.territory == "DEU" })
        #expect(germany.oldAmount == Money(string: "3.99"))
        #expect(germany.newAmount == Money(string: "4.99"))
        #expect(germany.direction == .up)
        #expect(preview.origin == .network)

        let onDisk = try ProductStore.load(in: fixture.load()).products["com.example.pro"]
        #expect(onDisk?.price == nil)
    }

    /// The ladder a preview read is kept, so writing the same plan next costs
    /// no second ladder read.
    @Test func aPlanWrittenAfterAPreviewReadsNoLadder() async throws {
        var unpriced = Self.subscription
        unpriced.price = nil
        try fixture.writeProduct(unpriced)

        let first = transport()
        let match = try await remoteProduct(on: first)
        let plan = try #require(Self.subscription.price)
        _ = try await session(on: first).readProductPrices(of: unpriced, plan: plan, on: match)

        try fixture.writeProduct(Self.subscription)
        let second = transport()
        try await session(on: second).read(prices: .cached)

        #expect(await ladderRequests(second) == 0)
    }

    /// A base price that is not on the ladder gets no anchors. Only the base
    /// country gets a price, and the preview names every other country as left
    /// out instead of inventing prices.
    @Test func aPreviewOfAPriceOffTheLadderSaysWhatIsWrong() async throws {
        let transport = transport()
        let match = try await remoteProduct(on: transport)
        var plan = try #require(Self.subscription.price)
        plan.baseAmount = try #require(Money(string: "4.50"))

        let preview = try await session(on: transport)
            .readProductPrices(of: Self.subscription, plan: plan, on: match)

        let change = try #require(preview.change)
        #expect(Set(change.rows.map(\.territory)) == ["USA"])
        #expect(change.skipped.contains { $0.territory == "DEU" })

        // Germany would get whatever App Store Connect picks, so the plan
        // names it and no price of this product may go.
        #expect(change.unpriced.contains("DEU"))
        #expect(preview.blocked.isEmpty == false)
    }

    /// A push refuses a product with a country that has no price, and sends
    /// nothing for it.
    @Test func aPushSendsNoPriceWhileACountryHasNone() async throws {
        // 3.50 is off the ladder, and rounds to 3.99 in the United States,
        // which pays 4.99 today. So the plan changes a price.
        var plan = try #require(Self.subscription.price)
        plan.baseAmount = try #require(Money(string: "3.50"))
        var offTheLadder = Self.subscription
        offTheLadder.price = plan
        try fixture.writeProduct(offTheLadder)

        let transport = transport()
        let session = try session(on: transport)
        let reading = try await session.read(prices: .fresh)
        let outcome = try await session.pushPrices(reading, dryRun: true)

        #expect(outcome.result.wouldSend.isEmpty)
        #expect(outcome.result.failed.contains { $0.productID == "com.example.pro" })
    }

    /// With no plan, only the prices of today are read. That is one request
    /// and no ladder.
    @Test func readingAProductWithNoPlanReadsNoLadder() async throws {
        let transport = transport()
        let match = try await remoteProduct(on: transport)
        let before = await ladderRequests(transport)

        let reading = try await session(on: transport)
            .readProductPrices(of: Self.subscription, plan: nil, on: match)

        #expect(await ladderRequests(transport) == before)
        #expect(reading.current["DEU"] == Money(string: "3.99"))
        #expect(reading.change == nil)
        #expect(reading.origin == nil)
    }

    /// Fresh reads the ladder again, the way the read button on the price page
    /// does, even with a kept copy on disk.
    @Test func aFreshProductReadReadsTheLadderAgain() async throws {
        let transport = transport()
        let match = try await remoteProduct(on: transport)
        let plan = try #require(Self.subscription.price)
        _ = try await session(on: transport).readProductPrices(of: Self.subscription, plan: plan, on: match)
        let first = await ladderRequests(transport)

        let reading = try await session(on: transport)
            .readProductPrices(of: Self.subscription, plan: plan, on: match, source: .fresh)

        #expect(await ladderRequests(transport) > first)
        #expect(reading.origin == .network)
    }

    // MARK: - A kept ladder plans the same push

    /// If these two differed, a push after a cached read would be refused every
    /// time, and the whole cache would be useless.
    @Test func aPlanOffTheDiskIsThePlanOffTheNetwork() async throws {
        let first = try await session(on: transport()).read(prices: .fresh)
        let cached = try await session(on: transport()).read(prices: .cached)

        #expect(cached.changes?.agreementDigest == first.changes?.agreementDigest)
        #expect(cached.changes?.digest == first.changes?.digest)
    }

    /// Apple regenerates price point identifiers. A push writes the second
    /// read's plan, so a plan read off the disk still agrees with one whose
    /// identifiers all moved.
    @Test func aPlanOffTheDiskStillAgreesWhenAppleRegeneratesTheIdentifiers() async throws {
        let cached = try await session(on: transport()).read(prices: .cached)
        let again = try await session(on: transport(ladderIDSuffix: "-v2")).read(prices: .fresh)

        #expect(cached.changes?.agreementDigest == again.changes?.agreementDigest)
        #expect(cached.changes?.digest != again.changes?.digest)
    }

    /// The rows a push sends carry Apple's real identifiers, not a stand-in.
    @Test func aPlanOffTheDiskCarriesRealPricePointIdentifiers() async throws {
        try await session(on: transport()).read(prices: .fresh)
        let reading = try await session(on: transport()).read(prices: .cached)

        let plan = try #require(reading.changes?.pricePlans.first)
        #expect(plan.rows.isEmpty == false)
        #expect(plan.rows.allSatisfy { $0.pricePointID.isEmpty == false })
        #expect(plan.rows.allSatisfy { $0.pricePointID != PricePointCache.notReadIdentifier })
    }

    /// The number the table calls "old" is read every time, so it cannot go
    /// stale and hide a rise.
    @Test func aCachedReadStillSeesGermanyAsARise() async throws {
        try await session(on: transport()).read(prices: .fresh)
        let reading = try await session(on: transport()).read(prices: .cached)

        let rises = try #require(reading.changes?.priceRises)
        #expect(rises.contains { $0.territory == "DEU" })
    }
}
