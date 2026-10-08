import ASCKitTestSupport
import Foundation
import Testing
@testable import ASCKitAPI

/// Reading a catalogue of in-app purchases, against recorded replies.
struct ProductReaderTests {
    static let app = #"{"data":[{"type":"apps","id":"a1","attributes":{"name":"MyApp"}}]}"#

    static let purchases = """
    {"data":[
      {"type":"inAppPurchases","id":"p1","attributes":{
        "name":"Lifetime","productId":"com.example.lifetime",
        "inAppPurchaseType":"NON_CONSUMABLE","state":"APPROVED",
        "reviewNote":"Restores across devices.","familySharable":true}},
      {"type":"inAppPurchases","id":"p2","attributes":{
        "name":"Tip","productId":"com.example.tip",
        "inAppPurchaseType":"CONSUMABLE","state":"READY_TO_SUBMIT"}}
    ]}
    """

    static let groups = """
    {"data":[{"type":"subscriptionGroups","id":"g1",
              "attributes":{"referenceName":"Pro"}}]}
    """

    static let subscriptions = """
    {"data":[{"type":"subscriptions","id":"s1","attributes":{
      "name":"Pro Monthly","productId":"com.example.pro.monthly",
      "subscriptionPeriod":"ONE_MONTH","state":"APPROVED","groupLevel":1}}]}
    """

    static let purchaseWords = """
    {"data":[{"type":"inAppPurchaseLocalizations","id":"l1","attributes":{
      "locale":"en-US","name":"Lifetime","description":"Pro, once, forever."}}]}
    """

    static let subscriptionWords = """
    {"data":[{"type":"subscriptionLocalizations","id":"l9","attributes":{
      "locale":"de-DE","name":"Pro Monatlich","description":"Alles in Pro."}}]}
    """

    static let groupWords = """
    {"data":[{"type":"subscriptionGroupLocalizations","id":"g-en","attributes":{
      "locale":"en-US","name":"Pro","customAppName":"MyApp Pro"}}]}
    """

    /// One draft, which is what a product being worked on looks like.
    static func versions(_ type: String, id: String) -> String {
        """
        {"data":[{"type":"\(type)","id":"\(id)","attributes":{
          "version":3,"state":"PREPARE_FOR_SUBMISSION"}}]}
        """
    }

    /// The order these arrive in is not decided by anything, because the reader
    /// asks for them at the same time. So the stub answers by path.
    ///
    /// Longest first, and the version routes before the product ones. The
    /// words of a product live under a version, so a route matching
    /// `/subscriptions` would answer a version call with the subscription
    /// itself. A route on `/localizations` alone would answer all three kinds
    /// of words with one of them.
    static var routes: [(String, StubTransport.Reply)] {
        [
            ("/inAppPurchaseVersions", .ok(purchaseWords)),
            ("/subscriptionGroupVersions", .ok(groupWords)),
            ("/subscriptionVersions", .ok(subscriptionWords)),
            ("/inAppPurchases/", .ok(versions("inAppPurchaseVersions", id: "pv1"))),
            ("/inAppPurchasesV2", .ok(purchases)),
            (
                "/subscriptionGroups/g1/versions",
                .ok(versions("subscriptionGroupVersions", id: "gv1"))
            ),
            ("/subscriptionGroups/g1/subscriptions", .ok(subscriptions)),
            ("/subscriptions/s1/versions", .ok(versions("subscriptionVersions", id: "sv1"))),
            ("/subscriptionGroups", .ok(groups)),
            ("/apps", .ok(app))
        ]
    }

    func read() async throws -> RemoteProducts {
        let client = try ASCClient.stubbed(transport: StubTransport(routes: Self.routes))
        return try await client.products(bundleID: "com.example.MyApp")
    }

    /// One version, as a test says it.
    struct Version {
        let id: String
        let number: Int
        let state: String
    }

    /// A version list, so a test says only which versions the store holds.
    static func list(_ rows: [Version]) -> String {
        """
        {"data":[
        \(rows.map { """
          {"type":"inAppPurchaseVersions","id":"\($0.id)","attributes":{
            "version":\($0.number),"state":"\($0.state)"}}
        """ }.joined(separator: ","))
        ]}
        """
    }

    /// The same read, with the one-time purchase's versions answered
    /// differently.
    func read(purchaseVersions: String) async throws -> RemoteProducts {
        let routes = [("/inAppPurchases/", StubTransport.Reply.ok(purchaseVersions))]
            + Self.routes
        let client = try ASCClient.stubbed(transport: StubTransport(routes: routes))
        return try await client.products(bundleID: "com.example.MyApp")
    }

    /// The same read, with the one-time purchase's words answered differently.
    func read(purchaseWords: String) async throws -> RemoteProducts {
        let routes = [("/inAppPurchaseVersions", StubTransport.Reply.ok(purchaseWords))]
            + Self.routes.dropFirst()
        let client = try ASCClient.stubbed(transport: StubTransport(routes: routes))
        return try await client.products(bundleID: "com.example.MyApp")
    }

    // MARK: - Both kinds

    /// Two kinds of product arrive by two different routes, and a subscription
    /// takes an extra hop through its group.
    @Test func readsOneTimePurchasesAndSubscriptionsTogether() async throws {
        let found = try await read()
        #expect(found.products.map(\.productID) == [
            "com.example.lifetime", "com.example.pro.monthly", "com.example.tip"
        ])
    }

    @Test func writesTheKindTheWayAFileWritesIt() async throws {
        let found = try await read().byProductID
        #expect(found["com.example.lifetime"]?.kind == "non_consumable")
        #expect(found["com.example.tip"]?.kind == "consumable")
        #expect(found["com.example.pro.monthly"]?.kind == "auto_renewable_subscription")
    }

    /// A kind Apple adds later keeps its own word rather than being guessed at,
    /// so the validator reports it instead of the reader hiding it.
    @Test func keepsAKindItDoesNotRecognise() async throws {
        var routes = Self.routes
        routes[4] = ("/inAppPurchasesV2", .ok("""
        {"data":[{"type":"inAppPurchases","id":"p9","attributes":{
          "productId":"com.example.odd","inAppPurchaseType":"SOMETHING_NEW"}}]}
        """))
        let client = try ASCClient.stubbed(transport: StubTransport(routes: routes))
        let found = try await client.products(bundleID: "com.example.MyApp").byProductID
        #expect(found["com.example.odd"]?.kind == "something_new")
    }

    @Test func carriesTheGroupNameOntoEverySubscriptionInIt() async throws {
        let found = try await read().byProductID
        #expect(found["com.example.pro.monthly"]?.subscriptionGroup == "Pro")
        #expect(found["com.example.pro.monthly"]?.subscriptionPeriod == "ONE_MONTH")
        // Only a subscription belongs to a group.
        #expect(found["com.example.tip"]?.subscriptionGroup == nil)
    }

    @Test func readsTheStateAndTheReviewNote() async throws {
        let found = try await read().byProductID
        #expect(found["com.example.lifetime"]?.state == "APPROVED")
        #expect(found["com.example.lifetime"]?.reviewNote == "Restores across devices.")
        #expect(found["com.example.lifetime"]?.familySharable == true)
    }

    // MARK: - Words

    /// The two kinds keep their words on two different resources holding the
    /// same two fields.
    @Test func readsWordsFromWhicheverEndpointTheKindUses() async throws {
        let found = try await read().byProductID
        #expect(found["com.example.lifetime"]?.localizations["en-US"]?.name == "Lifetime")
        #expect(found["com.example.pro.monthly"]?
            .localizations["de-DE"]?.name == "Pro Monatlich")
    }

    /// An update needs the id of the localization, not only its language.
    @Test func keepsTheIdOfEveryLanguageItRead() async throws {
        let found = try await read().byProductID
        #expect(found["com.example.lifetime"]?.localizations["en-US"]?.id == "l1")
    }

    // MARK: - Which version the words come out of

    /// A product being worked on has a draft beside the versions review has
    /// already seen, and the draft is the one to read. It is what App Store
    /// Connect shows and what a push writes.
    ///
    /// Both orders, because the list arrives in neither one reliably.
    @Test(arguments: [
        [Version(id: "old", number: 2, state: "APPROVED"),
         Version(id: "draft", number: 3, state: "PREPARE_FOR_SUBMISSION")],
        [Version(id: "draft", number: 3, state: "PREPARE_FOR_SUBMISSION"),
         Version(id: "old", number: 2, state: "APPROVED")]
    ])
    func readsTheDraftWhenTheStoreHoldsOne(rows: [Version]) async throws {
        let found = try await read(purchaseVersions: Self.list(rows)).byProductID
        let product = try #require(found["com.example.lifetime"])
        #expect(product.version?.id == "draft")
        #expect(product.version?.number == 3)
        #expect(product.version?.acceptsChanges == true)
    }

    /// With no draft, the words a product sells under today still come back, so
    /// the app and a pull show something. Only a push needs a draft.
    ///
    /// The newest by Apple's counter, not the approved one: a version in review
    /// holds newer words, and the counter says which without guessing at the
    /// order of a state machine.
    @Test func readsTheNewestVersionWhenThereIsNoDraft() async throws {
        let rows = [
            Version(id: "old", number: 2, state: "APPROVED"),
            Version(id: "newer", number: 3, state: "IN_REVIEW")
        ]
        let found = try await read(purchaseVersions: Self.list(rows)).byProductID
        let product = try #require(found["com.example.lifetime"])
        #expect(product.version?.id == "newer")
        #expect(product.version?.acceptsChanges == false)
    }

    /// App Store Connect refuses a change to the words of a version that
    /// review has seen, with "Version is not in modifiable state". Only a
    /// draft takes one.
    @Test(arguments: [
        ("PREPARE_FOR_SUBMISSION", true), ("APPROVED", false), ("ACCEPTED", false),
        ("READY_FOR_REVIEW", false), ("REJECTED", false), ("DEVELOPER_REJECTED", false)
    ])
    func acceptsChangesOnlyInADraft(state: String, accepts: Bool) async throws {
        let rows = [Version(id: "only", number: 1, state: state)]
        let found = try await read(purchaseVersions: Self.list(rows)).byProductID
        #expect(found["com.example.lifetime"]?.version?.acceptsChanges == accepts)
    }

    /// A version Apple has already superseded is not what the store sells
    /// under, even when its number is the highest.
    @Test func passesOverAVersionThatWasReplaced() async throws {
        let rows = [
            Version(id: "current", number: 2, state: "APPROVED"),
            Version(id: "gone", number: 3, state: "REPLACED_WITH_NEW_VERSION")
        ]
        let found = try await read(purchaseVersions: Self.list(rows)).byProductID
        #expect(found["com.example.lifetime"]?.version?.id == "current")
    }

    /// A product with no version has no words, and the read makes none. ASCKit
    /// never creates a version, so the push refuses this product and says to
    /// make the draft in App Store Connect.
    @Test func readsNoWordsForAProductWithNoVersion() async throws {
        let transport = StubTransport(
            routes: [("/inAppPurchases/", StubTransport.Reply.ok(#"{"data":[]}"#))]
                + Self.routes
        )
        let client = try ASCClient.stubbed(transport: transport)
        let found = try await client.products(bundleID: "com.example.MyApp").byProductID

        let product = try #require(found["com.example.lifetime"])
        #expect(product.version == nil)
        #expect(product.localizations.isEmpty)

        let paths = await transport.requests.compactMap { $0.url?.path }
        #expect(paths.contains { $0.contains("/inAppPurchaseVersions") } == false)
    }

    @Test func skipsTheWordsWhenNobodyAsksForThem() async throws {
        let transport = StubTransport(routes: Self.routes)
        let client = try ASCClient.stubbed(transport: transport)
        let found = try await client.products(bundleID: "com.example.MyApp", includeWords: false)

        let withWords = found.products.filter { $0.localizations.isEmpty == false }
        #expect(withWords.isEmpty)

        let paths = await transport.requests.compactMap { $0.url?.path }
        #expect(paths.contains { $0.contains("localizations") } == false)
        #expect(paths.contains { $0.hasSuffix("/versions") } == false)
    }

    // MARK: - Nothing there

    @Test func readsAnAppWithNoPurchasesAtAll() async throws {
        let routes: [(String, StubTransport.Reply)] = [
            ("/inAppPurchasesV2", .ok(#"{"data":[]}"#)),
            ("/subscriptionGroups", .ok(#"{"data":[]}"#)),
            ("/apps", .ok(Self.app))
        ]
        let client = try ASCClient.stubbed(transport: StubTransport(routes: routes))
        #expect(try await client.products(bundleID: "com.example.MyApp").products.isEmpty)
    }

    @Test func refusesABundleIdentifierTheStoreDoesNotHave() async throws {
        let client = try ASCClient.stubbed(
            transport: StubTransport(routes: [("/apps", .ok(#"{"data":[]}"#))])
        )
        await #expect(throws: ListingError.self) {
            try await client.products(bundleID: "com.example.nope")
        }
    }
}
