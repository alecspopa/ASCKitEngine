import ASCKitAPI
import ASCKitTestSupport
import Foundation
import Testing
@testable import ASCKitProject

struct ProductPusherTests {
    static let priceReply = #"{"data":{"type":"subscriptionPrices","id":"x"}}"#
    static let wordsReply = #"{"data":{"type":"subscriptionLocalizations","id":"l1"}}"#
    static let purchaseWordsReply = #"{"data":{"type":"inAppPurchaseLocalizations","id":"l1"}}"#
    static let refusal = #"{"errors":[{"detail":"Not allowed here."}]}"#
    static let subscriptionReply = #"{"data":{"type":"subscriptions","id":"s1"}}"#

    func row(
        _ territory: String,
        _ amount: Money,
        old: Money? = "1.99",
        direction: ChangePlan.PriceChange.Direction = .up,
        planType: ChangePlan.PriceChange.PlanType = .upfront
    ) -> ChangePlan.PriceChange.Row {
        ChangePlan.PriceChange.Row(
            territory: territory,
            planType: planType,
            currency: "USD",
            pricePointID: "point-\(territory)",
            oldAmount: old,
            newAmount: amount,
            direction: direction,
            source: .curve(band: nil),
            roundedUpBy: "0"
        )
    }

    func plan(
        kind: Product.Kind = .autoRenewableSubscription,
        rows: [ChangePlan.PriceChange.Row],
        preserveCurrentPrice: Bool? = true,
        productText: [ChangePlan.ProductTextChange] = []
    ) -> ChangePlan {
        ChangePlan(
            versionString: "1.0",
            versionState: nil,
            textChanges: [],
            missingLocales: [],
            screenshotPlans: [],
            productTextChanges: productText,
            pricePlans: rows.isEmpty ? [] : [ChangePlan.PriceChange(
                productID: "com.example.pro",
                kind: kind,
                baseTerritory: "USA",
                baseAmount: "4.99",
                curveID: "purchasing-power",
                replacesWholeSchedule: kind.priceWriteReplacesEveryTerritory,
                preserveCurrentPrice: kind.isAutoRenewable ? preserveCurrentPrice : nil,
                rows: rows,
                skipped: []
            )],
            newProducts: [],
            blocked: [],
            skipped: []
        )
    }

    /// A draft by default. A push writes the words into a version, so a product
    /// without one is refused rather than written to.
    func remote(
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
                version: version,
                localizations: localizations
            )],
            groupNames: [:]
        )
    }

    // MARK: - Prices, every country at once

    /// The default. A subscription has no price schedule but it does take a
    /// compound update, so a change everywhere is one request rather than one
    /// per country.
    @Test func writesOneRequestForAWholeSubscription() async throws {
        let transport = StubTransport(.ok(Self.subscriptionReply))
        let client = try ASCClient.stubbed(transport: transport)

        let result = await ProductPusher(client: client).pushPrices(
            plan(rows: [row("USA", "2.99"), row("DEU", "3.99"), row("IND", "199")]),
            to: remote()
        )

        #expect(await transport.requestCount == 1)
        #expect(result.written.count == 3)
        #expect(result.isCompleteSuccess)
    }

    /// Every country, not only the ones that change. Apple never says whether
    /// this update replaces the price set or adds to it, and sending all of
    /// them is right either way.
    @Test func sendsEvenTheCountriesThatDoNotChange() async throws {
        let transport = StubTransport(.ok(Self.subscriptionReply))
        let client = try ASCClient.stubbed(transport: transport)

        _ = await ProductPusher(client: client).pushPrices(
            plan(rows: [
                row("USA", "2.99"),
                row("DEU", "3.99", old: "3.99", direction: .same)
            ]),
            to: remote()
        )

        let body = await String(
            data: transport.request(at: 0).httpBody ?? Data(), encoding: .utf8
        ) ?? ""
        #expect(body.contains("DEU"))
        #expect(body.contains("USA"))
    }

    /// One request, so a refusal is one refusal rather than a list.
    ///
    /// The message must not claim nothing was written. Apple does not say that
    /// a rejected request of this shape is applied all or nothing, and telling
    /// somebody their prices are untouched when they might not be is worse than
    /// telling them to look.
    @Test func reportsARefusedSubscriptionUpdateWithoutPromisingNothingLanded() async throws {
        let transport = StubTransport(.failure(409, Self.refusal))
        let client = try ASCClient.stubbed(transport: transport)

        let result = await ProductPusher(client: client).pushPrices(
            plan(rows: [row("USA", "2.99"), row("DEU", "3.99")]),
            to: remote()
        )

        #expect(result.written.isEmpty)
        #expect(result.failed.count == 1)

        let reason = try #require(result.failed.first?.reason)
        #expect(reason.contains("read it back rather than assuming"))
        #expect(reason.contains("--one-country-at-a-time"))
    }

    @Test func showsOneBodyForAWholeSubscriptionOnADryRun() async throws {
        let transport = StubTransport(routes: [("/", .ok("{}"))])
        let client = try ASCClient.stubbed(transport: transport)

        let result = await ProductPusher(client: client).pushPrices(
            plan(rows: [row("USA", "2.99"), row("DEU", "3.99")]),
            to: remote(),
            dryRun: true
        )

        #expect(await transport.requestCount == 0)
        #expect(result.wouldSend.count == 1)
        #expect(result.wouldSend[0].contains("${price-USA-UPFRONT}"))
    }

    // MARK: - Prices, one country at a time

    /// The fallback, for when the one request comes back refused without
    /// saying which country it objected to.
    @Test func writesOneRequestPerCountryWhenAsked() async throws {
        let transport = StubTransport(routes: [("/subscriptionPrices", .ok(Self.priceReply))])
        let client = try ASCClient.stubbed(transport: transport)

        let result = await ProductPusher(client: client).pushPrices(
            plan(rows: [row("USA", "2.99"), row("DEU", "3.99"), row("IND", "199")]),
            to: remote(),
            oneCountryAtATime: true
        )

        #expect(await transport.requestCount == 3)
        #expect(result.written.count == 3)
        #expect(result.isCompleteSuccess)
    }

    /// One country failing does not stop the rest, because the ones that go are
    /// worth having and the ones that do not can be tried again.
    @Test func keepsGoingAfterOneCountryFails() async throws {
        // Routed by what the body says rather than by arrival order, because
        // the countries are written at the same time and nothing decides which
        // one reaches the stub first.
        let transport = StubTransport(
            bodyRoutes: [("IND", .failure(409, Self.refusal))],
            otherwise: .ok(Self.priceReply)
        )
        let client = try ASCClient.stubbed(transport: transport)

        let result = await ProductPusher(client: client).pushPrices(
            plan(rows: [row("DEU", "3.99"), row("IND", "199"), row("USA", "2.99")]),
            to: remote(),
            oneCountryAtATime: true
        )

        #expect(await transport.requestCount == 3)
        #expect(result.written.map(\.territory) == ["DEU", "USA"])
        #expect(result.failed.map(\.what) == ["IND"])
        #expect(result.isCompleteSuccess == false)
    }

    /// The countries that failed have to be findable, or nobody can tell what
    /// to try again.
    @Test func namesTheCountriesToTryAgain() async throws {
        let transport = StubTransport(
            bodyRoutes: [("DEU", .failure(409, Self.refusal))],
            otherwise: .ok(Self.priceReply)
        )
        let client = try ASCClient.stubbed(transport: transport)

        let result = await ProductPusher(client: client).pushPrices(
            plan(rows: [row("DEU", "3.99"), row("USA", "2.99")]),
            to: remote(),
            oneCountryAtATime: true
        )
        #expect(result.retryable == ["DEU"])
        #expect(result.failed.first?.reason.isEmpty == false)
    }

    @Test func carriesWhetherExistingSubscribersWereProtected() async throws {
        let transport = StubTransport(routes: [("/subscriptionPrices", .ok(Self.priceReply))])
        let client = try ASCClient.stubbed(transport: transport)

        let result = await ProductPusher(client: client).pushPrices(
            plan(rows: [row("USA", "2.99")], preserveCurrentPrice: false),
            to: remote(),
            oneCountryAtATime: true
        )
        #expect(result.written.first?.preservedCurrentPrice == false)
    }

    // MARK: - Prices, all at once

    /// A schedule replaces the one before it, so it goes in one request or the
    /// countries left out fall back to Apple's own price.
    @Test func writesOneRequestForAOneTimePurchase() async throws {
        let transport = StubTransport(.ok(#"{"data":{"type":"inAppPurchasePriceSchedules","id":"x"}}"#))
        let client = try ASCClient.stubbed(transport: transport)

        let result = await ProductPusher(client: client).pushPrices(
            plan(kind: .nonConsumable, rows: [row("USA", "2.99"), row("DEU", "3.99")]),
            to: remote(kind: "non_consumable")
        )

        #expect(await transport.requestCount == 1)
        #expect(result.written.count == 2)
    }

    /// The whole schedule goes in one request, so there is no half of it to
    /// report.
    @Test func reportsAFailedScheduleAsOneThingRatherThanPerCountry() async throws {
        let transport = StubTransport(.failure(409, #"{"errors":[{"detail":"No."}]}"#))
        let client = try ASCClient.stubbed(transport: transport)

        let result = await ProductPusher(client: client).pushPrices(
            plan(kind: .nonConsumable, rows: [row("USA", "2.99"), row("DEU", "3.99")]),
            to: remote(kind: "non_consumable")
        )

        #expect(result.written.isEmpty)
        #expect(result.failed.count == 1)
        #expect(result.failed.first?.what == "")
    }

    // MARK: - Looking without writing

    /// One body per country on the fallback path, and one for the whole
    /// subscription on the default one, which the two tests above cover.
    @Test func showsOneBodyPerCountryOnTheFallbackDryRun() async throws {
        let transport = StubTransport(routes: [("/", .ok("{}"))])
        let client = try ASCClient.stubbed(transport: transport)

        let result = await ProductPusher(client: client).pushPrices(
            plan(rows: [row("USA", "2.99"), row("DEU", "3.99")]),
            to: remote(),
            dryRun: true,
            oneCountryAtATime: true
        )

        #expect(await transport.requestCount == 0)
        #expect(result.written.isEmpty)
        #expect(result.wouldSend.count == 2)
        #expect(result.wouldSend[0].contains("subscriptionPrices"))
    }

    @Test func showsOneBodyForAOneTimePurchaseHoweverManyCountries() async throws {
        let transport = StubTransport(routes: [("/", .ok("{}"))])
        let client = try ASCClient.stubbed(transport: transport)

        let result = await ProductPusher(client: client).pushPrices(
            plan(kind: .nonConsumable, rows: [row("USA", "2.99"), row("DEU", "3.99")]),
            to: remote(kind: "non_consumable"),
            dryRun: true
        )
        #expect(result.wouldSend.count == 1)
        #expect(result.wouldSend[0].contains("baseTerritory"))
    }

    // MARK: - Words

    @Test func createsALanguageTheStoreDoesNotHave() async throws {
        let transport = StubTransport(routes: [("/subscriptionLocalizations", .ok(Self.wordsReply))])
        let client = try ASCClient.stubbed(transport: transport)

        let result = await ProductPusher(client: client).pushText(
            plan(rows: [], productText: [
                .init(productID: "com.example.pro", locale: "de-DE", field: .name,
                      action: .add, oldValue: nil, newValue: "Pro"),
                .init(productID: "com.example.pro", locale: "de-DE", field: .description,
                      action: .add, oldValue: nil, newValue: "Alles in Pro.")
            ]),
            to: remote()
        )

        // Both fields go together, because App Store Connect wants both on a
        // create and there is no reason to make two calls.
        #expect(await transport.requestCount == 1)
        #expect(await transport.request(at: 0).httpMethod == "POST")
        #expect(result.isCompleteSuccess)
    }

    @Test func changesALanguageTheStoreAlreadyHas() async throws {
        let transport = StubTransport(routes: [("/subscriptionLocalizations", .ok(Self.wordsReply))])
        let client = try ASCClient.stubbed(transport: transport)

        _ = await ProductPusher(client: client).pushText(
            plan(rows: [], productText: [
                .init(productID: "com.example.pro", locale: "de-DE", field: .name,
                      action: .change, oldValue: "Alt", newValue: "Neu")
            ]),
            to: remote(localizations: [
                "de-DE": .init(id: "l1", locale: "de-DE", name: "Alt", description: "Alt.")
            ])
        )

        let request = await transport.request(at: 0)
        #expect(request.httpMethod == "PATCH")
        #expect(request.url?.path == "/v2/subscriptionLocalizations/l1")
    }

    /// A language the draft does not hold is added to it, carrying both
    /// fields, because a new row needs the pair.
    ///
    /// Both fields are in the plan: the draft holds nothing for this language,
    /// so the planner reads every field as an add.
    @Test func makesALanguageTheDraftDoesNotHold() async throws {
        let transport = StubTransport(routes: [("/subscriptionLocalizations", .ok(Self.wordsReply))])
        let client = try ASCClient.stubbed(transport: transport)

        let result = await ProductPusher(client: client).pushText(
            plan(rows: [], productText: [
                .init(productID: "com.example.pro", locale: "de-DE", field: .name,
                      action: .add, oldValue: nil, newValue: "Pro"),
                .init(productID: "com.example.pro", locale: "de-DE", field: .description,
                      action: .add, oldValue: nil, newValue: "Neu.")
            ]),
            to: remote()
        )

        let request = await transport.request(at: 0)
        #expect(request.httpMethod == "POST")
        #expect(result.isCompleteSuccess)

        let body = try #require(request.httpBody.flatMap { String(data: $0, encoding: .utf8) })
        #expect(body.contains(#""name":"Pro""#))
        #expect(body.contains("Neu."))
        // The row belongs to the draft, which somebody made in App Store
        // Connect. ASCKit never makes one.
        #expect(body.contains(#""subscriptionVersions""#))
        #expect(body.contains(#""v1""#))
    }

    /// The rule the whole migration turns on: with no draft to write into,
    /// nothing is sent at all.
    ///
    /// Asserting on the requests rather than only on the failure. A test that
    /// read the message alone would still pass if somebody added a version
    /// create back.
    @Test func sendsNothingForAProductWithNoDraft() async throws {
        let transport = StubTransport(routes: [("/", .ok(Self.wordsReply))])
        let client = try ASCClient.stubbed(transport: transport)

        let result = await ProductPusher(client: client).pushText(
            plan(rows: [], productText: [
                .init(productID: "com.example.pro", locale: "de-DE", field: .name,
                      action: .add, oldValue: nil, newValue: "Pro")
            ]),
            to: remote(version: nil)
        )

        #expect(await transport.requests.isEmpty)
        #expect(result.written.isEmpty)
        #expect(result.drafts.isEmpty)
        #expect(result.failed.map(\.productID) == ["com.example.pro"])
        // Empty, the way it is when a whole product failed.
        #expect(result.failed.map(\.what) == [""])
        // The languages that did not go are named, or nobody can tell from the
        // receipt what was skipped.
        #expect(result.failed.first?.reason.contains("de-DE") == true)
    }

    /// A version App Review has already seen takes no change, and says so
    /// differently: the answer is a new version rather than a first one.
    @Test func sendsNothingWhenTheOnlyVersionIsClosed() async throws {
        let transport = StubTransport(routes: [("/", .ok(Self.wordsReply))])
        let client = try ASCClient.stubbed(transport: transport)

        let result = await ProductPusher(client: client).pushText(
            plan(rows: [], productText: [
                .init(productID: "com.example.pro", locale: "de-DE", field: .name,
                      action: .add, oldValue: nil, newValue: "Pro")
            ]),
            to: remote(version: RemoteProductVersion(id: "v9", number: 4, state: .inReview))
        )

        #expect(await transport.requests.isEmpty)
        #expect(result.failed.first?.reason.contains("in review") == true)
    }

    /// A dry run refuses wherever a real run would, so nobody reads a body
    /// that was never going to go.
    ///
    /// A new row needs a name. Without one the real write throws, and printing
    /// a body with an empty name would say the opposite.
    @Test func aDryRunRefusesALanguageWithNoName() async throws {
        let client = try ASCClient.stubbed(transport: StubTransport(.ok(Self.wordsReply)))

        let result = await ProductPusher(client: client).pushText(
            plan(rows: [], productText: [
                .init(productID: "com.example.pro", locale: "de-DE", field: .description,
                      action: .add, oldValue: nil, newValue: "Neu.")
            ]),
            to: remote(),
            dryRun: true
        )

        #expect(result.wouldSend.isEmpty)
        #expect(result.failed.map(\.what) == ["de-DE"])
    }

    /// A dry run builds every body and sends none of them, the way a price dry
    /// run does.
    @Test func aDryRunOfTheWordsSendsNothing() async throws {
        let transport = StubTransport(routes: [("/", .ok(Self.wordsReply))])
        let client = try ASCClient.stubbed(transport: transport)

        let result = await ProductPusher(client: client).pushText(
            plan(rows: [], productText: [
                .init(productID: "com.example.pro", locale: "de-DE", field: .name,
                      action: .add, oldValue: nil, newValue: "Pro")
            ]),
            to: remote(),
            dryRun: true
        )

        #expect(await transport.requests.isEmpty)
        #expect(result.written.isEmpty)
        #expect(result.wouldSend.count == 1)
        #expect(result.wouldSend[0].contains(#""subscriptionVersions""#))
        #expect(result.wouldSend[0].contains(#""Pro""#))
    }

    @Test func keepsGoingAfterOneLanguageFails() async throws {
        let transport = StubTransport(
            bodyRoutes: [("de-DE", .failure(409, Self.refusal))],
            otherwise: .ok(Self.wordsReply)
        )
        let client = try ASCClient.stubbed(transport: transport)

        let result = await ProductPusher(client: client).pushText(
            plan(rows: [], productText: [
                .init(productID: "com.example.pro", locale: "de-DE", field: .name,
                      action: .add, oldValue: nil, newValue: "Pro"),
                .init(productID: "com.example.pro", locale: "en-US", field: .name,
                      action: .add, oldValue: nil, newValue: "Pro")
            ]),
            to: remote()
        )

        #expect(result.failed.map(\.what) == ["de-DE"])
        #expect(result.written == ["com.example.pro en-US"])
    }

    /// A one-time purchase keeps its words somewhere else entirely.
    @Test func writesAOneTimePurchasesWordsToTheOtherEndpoint() async throws {
        let transport = StubTransport(
            routes: [("/inAppPurchaseLocalizations", .ok(Self.purchaseWordsReply))]
        )
        let client = try ASCClient.stubbed(transport: transport)

        _ = await ProductPusher(client: client).pushText(
            plan(rows: [], productText: [
                .init(productID: "com.example.pro", locale: "en-US", field: .name,
                      action: .add, oldValue: nil, newValue: "Lifetime")
            ]),
            to: remote(kind: "non_consumable")
        )
        #expect(await transport.request(at: 0).url?.path == "/v2/inAppPurchaseLocalizations")
    }

    @Test func reportsAProductTheStoreNoLongerHas() async throws {
        let client = try ASCClient.stubbed(transport: StubTransport(routes: [("/", .ok("{}"))]))

        let result = await ProductPusher(client: client).pushPrices(
            plan(rows: [row("USA", "2.99")]),
            to: RemoteProducts(appID: "a1", products: [], groupNames: [:])
        )
        #expect(result.failed.first?.reason.contains("no longer has") == true)
    }
}
