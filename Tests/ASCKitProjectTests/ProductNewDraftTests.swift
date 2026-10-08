import ASCKitAPI
import ASCKitTestSupport
import Foundation
import Testing
@testable import ASCKitProject

/// A push that finds the words in a version that review is done with makes a
/// new draft first. App Store Connect copies the words into it, and the push
/// changes the copies.
struct ProductNewDraftTests {
    static let approved = RemoteProductVersion(id: "v4", number: 4, state: .approved)

    static func newVersion(_ type: String) -> String {
        """
        {"data":{"type":"\(type)","id":"v5","attributes":{
          "version":5,"state":"PREPARE_FOR_SUBMISSION"}}}
        """
    }

    /// The words that App Store Connect copied into the new draft, with ids of
    /// their own.
    static func copiedWords(_ type: String) -> String {
        """
        {"data":[{"type":"\(type)","id":"copy-de","attributes":{
          "locale":"de-DE","name":"Plus lebenslang","description":"Einmal zahlen."}}]}
        """
    }

    func plan(
        productText: [ChangePlan.ProductTextChange] = [],
        groupText: [ChangePlan.GroupTextChange] = []
    ) -> ChangePlan {
        ChangePlan(
            versionString: "1.0",
            versionState: nil,
            textChanges: [],
            missingLocales: [],
            screenshotPlans: [],
            productTextChanges: productText,
            groupTextChanges: groupText,
            blocked: [],
            skipped: []
        )
    }

    static let nameChange = ChangePlan.ProductTextChange(
        productID: "com.example.lifetime", locale: "de-DE", field: .name,
        action: .change, oldValue: "Plus lebenslang", newValue: "Premium lebenslang"
    )

    func remote(
        kind: String = "non_consumable",
        version: RemoteProductVersion? = ProductNewDraftTests.approved
    ) -> RemoteProducts {
        RemoteProducts(
            appID: "a1",
            products: [RemoteProduct(
                id: "p1",
                productID: "com.example.lifetime",
                kind: kind,
                version: version,
                localizations: [
                    "de-DE": .init(id: "old-de", locale: "de-DE", name: "Plus lebenslang")
                ]
            )],
            groupNames: [:]
        )
    }

    // MARK: - Pushing a product

    /// The route for the words of the new draft comes first. It is a path
    /// under the version, so the version route would answer it too.
    @Test(arguments: [
        ("non_consumable", "inAppPurchaseVersions", "inAppPurchaseLocalizations", "inAppPurchase"),
        ("auto_renewable_subscription", "subscriptionVersions", "subscriptionLocalizations", "subscription")
    ])
    func makesANewDraftAndChangesTheCopy(
        kind: String, versionType: String, wordsType: String, relationship: String
    ) async throws {
        let transport = StubTransport(routes: [
            ("/v5/localizations", .ok(Self.copiedWords(wordsType))),
            ("/v2/\(wordsType)/", .ok(#"{"data":{"type":"\#(wordsType)","id":"copy-de"}}"#)),
            ("/v1/\(versionType)", .ok(Self.newVersion(versionType)))
        ])
        let client = try ASCClient.stubbed(transport: transport)

        let result = await ProductPusher(client: client).pushText(
            plan(productText: [Self.nameChange]), to: remote(kind: kind)
        )

        #expect(result.isCompleteSuccess)
        #expect(result.written == ["com.example.lifetime de-DE"])
        #expect(result.drafts == [
            .init(productID: "com.example.lifetime", versionID: "v5", number: 5)
        ])

        let requests = await transport.requests
        #expect(requests.map { "\($0.httpMethod ?? "") \($0.url?.path ?? "")" } == [
            "POST /v1/\(versionType)",
            "GET /v1/\(versionType)/v5/localizations",
            "PATCH /v2/\(wordsType)/copy-de"
        ])
        let body = try #require(requests[0].httpBody.flatMap { String(data: $0, encoding: .utf8) })
        #expect(body.contains(#""\#(relationship)""#))
        #expect(body.contains(#""p1""#))
    }

    @Test func writesNothingWhenTheStoreRefusesTheNewDraft() async throws {
        let transport = StubTransport(routes: [
            ("/", .failure(409, #"{"errors":[{"detail":"A draft exists."}]}"#))
        ])
        let client = try ASCClient.stubbed(transport: transport)

        let result = await ProductPusher(client: client).pushText(
            plan(productText: [Self.nameChange]), to: remote()
        )

        #expect(await transport.requestCount == 1)
        #expect(result.written.isEmpty)
        #expect(result.drafts.isEmpty)
        #expect(result.failed.map(\.what) == [""])
        let reason = try #require(result.failed.first?.reason)
        #expect(reason.contains("new draft"))
        #expect(reason.contains("de-DE"))
    }

    /// A dry run shows the body that makes the draft, then the change to the
    /// copy. The copy has no id yet, so the change names a stand-in.
    @Test func aDryRunShowsTheNewDraftAndSendsNothing() async throws {
        let transport = StubTransport(routes: [("/", .ok("{}"))])
        let client = try ASCClient.stubbed(transport: transport)

        let result = await ProductPusher(client: client).pushText(
            plan(productText: [Self.nameChange]), to: remote(), dryRun: true
        )

        #expect(await transport.requests.isEmpty)
        #expect(result.drafts.isEmpty)
        #expect(result.wouldSend.count == 2)
        #expect(result.wouldSend[0].contains(#""inAppPurchaseVersions""#))
        #expect(result.wouldSend[1].contains("${new-draft-de-DE}"))
        #expect(result.wouldSend[1].contains("old-de") == false)
    }

    @Test(arguments: [ProductVersionState.inReview, .waitingForReview, .readyForReview])
    func makesNoDraftWhileReviewHasTheWords(state: ProductVersionState) async throws {
        let transport = StubTransport(routes: [("/", .ok("{}"))])
        let client = try ASCClient.stubbed(transport: transport)

        let result = await ProductPusher(client: client).pushText(
            plan(productText: [Self.nameChange]),
            to: remote(version: RemoteProductVersion(id: "v4", number: 4, state: state))
        )

        #expect(await transport.requests.isEmpty)
        #expect(result.failed.map(\.productID) == ["com.example.lifetime"])
    }

    // MARK: - Pushing a group

    @Test func makesANewDraftOfAGroup() async throws {
        let transport = StubTransport(routes: [
            ("/v5/localizations", .ok("""
            {"data":[{"type":"subscriptionGroupLocalizations","id":"copy-en","attributes":{
              "locale":"en-US","name":"Pro"}}]}
            """)),
            (
                "/v2/subscriptionGroupLocalizations/",
                .ok(#"{"data":{"type":"subscriptionGroupLocalizations","id":"copy-en"}}"#)
            ),
            ("/v1/subscriptionGroupVersions", .ok(Self.newVersion("subscriptionGroupVersions")))
        ])
        let client = try ASCClient.stubbed(transport: transport)
        let remote = RemoteProducts(
            appID: "a1",
            products: [],
            groupNames: ["g1": "Pro"],
            groups: [RemoteSubscriptionGroup(
                id: "g1",
                referenceName: "Pro",
                version: Self.approved,
                localizations: ["en-US": .init(id: "old-en", locale: "en-US", name: "Pro")]
            )]
        )

        let result = await ProductPusher(client: client).pushText(
            plan(groupText: [.init(
                group: "Pro", locale: "en-US", field: .name,
                action: .change, oldValue: "Pro", newValue: "Premium"
            )]),
            to: remote
        )

        #expect(result.written == ["Pro en-US"])
        let requests = await transport.requests
        #expect(requests.map { "\($0.httpMethod ?? "") \($0.url?.path ?? "")" } == [
            "POST /v1/subscriptionGroupVersions",
            "GET /v1/subscriptionGroupVersions/v5/localizations",
            "PATCH /v2/subscriptionGroupLocalizations/copy-en"
        ])
        let body = try #require(requests[0].httpBody.flatMap { String(data: $0, encoding: .utf8) })
        #expect(body.contains(#""subscriptionGroup""#))
        #expect(body.contains(#""g1""#))
    }

    // MARK: - Planning

    @Test(arguments: [ProductVersionState.approved, .accepted, .rejected, .developerRejected])
    func plansANewDraftWhenReviewIsDone(state: ProductVersionState) {
        let product = Product(
            productID: "com.example.lifetime",
            kind: Product.Kind.nonConsumable.rawValue,
            status: .approved,
            localizations: ["de-DE": .init(name: "Premium lebenslang", description: "Einmal zahlen.")]
        )
        let outcome = ProductPlanner.plan(
            local: ProductCatalog(products: [product.productID: product]),
            config: ProjectConfig(bundleID: "com.example.MyApp", keyID: "ABC123", locales: ["de-DE"]),
            remote: remote(version: RemoteProductVersion(id: "v4", number: 4, state: state))
        )

        #expect(outcome.blocked.isEmpty)
        #expect(outcome.newDrafts == ["com.example.lifetime"])
        #expect(outcome.textChanges.map(\.field) == [.name, .description])
    }

    @Test func thePlanSaysThatThePushMakesANewDraft() {
        var plan = plan(productText: [Self.nameChange])
        plan = ChangePlan(
            versionString: plan.versionString,
            versionState: nil,
            textChanges: [],
            missingLocales: [],
            screenshotPlans: [],
            productTextChanges: plan.productTextChanges,
            newDrafts: ["com.example.lifetime"],
            blocked: [],
            skipped: []
        )

        let text = ChangePlanFormatter.productWordLines(for: plan).joined(separator: " ")
        #expect(text.contains("new draft"))
        #expect(text.contains("com.example.lifetime"))
    }
}
