import ASCKitAPI
import ASCKitTestSupport
import Foundation
import Testing
@testable import ASCKitProject

final class SubscriptionGroupTests {
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

    func subscription(id: String = "com.example.pro.monthly", group: String = "Pro") -> Product {
        Product(
            productID: id,
            kind: Product.Kind.autoRenewableSubscription.rawValue,
            subscriptionGroup: group,
            subscriptionPeriod: "ONE_MONTH",
            status: .approved,
            localizations: [
                "en-US": .init(name: "Pro Monthly", description: "Everything in Pro, monthly."),
                "de-DE": .init(name: "Pro Monatlich", description: "Alles in Pro, monatlich.")
            ]
        )
    }

    func groupProblems() throws -> [Problem] {
        let project = try fixture.load()
        return Validator(config: project.config)
            .validate(ProductStore.load(in: project))
            .filter { $0.subscriptionGroup != nil }
    }

    // MARK: - Reading and writing

    @Test func readsAGroupBackUnderItsFileName() throws {
        try fixture.writeGroup(SubscriptionGroup(
            referenceName: "Premium",
            status: .needsHuman,
            localizations: ["en-US": .init(name: "Premium", customAppName: "My App")]
        ))

        let catalog = try fixture.products()

        #expect(catalog.groups["Premium"]?.referenceName == "Premium")
        #expect(catalog.groups["Premium"]?.status == .needsHuman)
        #expect(catalog.groups["Premium"]?.localizations["en-US"]?.customAppName == "My App")
        #expect(catalog.products.isEmpty)
        #expect(catalog.unreadable.isEmpty)
    }

    @Test func keepsTheNameOutOfTheFile() throws {
        try fixture.writeGroup()
        let url = try fixture.load().subscriptionGroupURL(name: "Pro")
        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text.contains("referenceName") == false)
    }

    @Test func refusesAGroupNameWithASlash() throws {
        #expect(throws: ContentWriteError.self) {
            try self.fixture.writeGroup(SubscriptionGroup(referenceName: "Pro/Plus"))
        }
    }

    @Test func listsAGroupASubscriptionNamesWithNoFile() throws {
        try fixture.writeProduct(subscription(group: "Premium"))
        let catalog = try fixture.products()

        #expect(catalog.groupNames == ["Premium"])
        #expect(catalog.subscriptions(in: "Premium").map(\.productID) == ["com.example.pro.monthly"])
    }

    // MARK: - Checking

    @Test func warnsAboutAGroupWithNoDisplayName() throws {
        try fixture.writeProduct(subscription())

        let problems = try groupProblems()

        #expect(problems.map(\.kind) == [.groupHasNoWords])
        #expect(problems.first?.severity == .warning)
        #expect(problems.first?.path == "products/groups/Pro.json")
    }

    @Test func saysNothingAboutAGroupWithWordsInEveryLanguage() throws {
        try fixture.writeProduct(subscription())
        try fixture.writeGroup()
        #expect(try groupProblems().isEmpty)
    }

    @Test func refusesADisplayNameOverTheLimit() throws {
        try fixture.writeGroup(SubscriptionGroup(
            referenceName: "Pro",
            localizations: [
                "en-US": .init(name: String(repeating: "a", count: 65)),
                "de-DE": .init(name: "Pro")
            ]
        ))

        let problems = try groupProblems()

        #expect(problems.map(\.kind) == [.groupTextOverLimit])
        #expect(problems.first?.groupField == .name)
    }

    @Test func takesAnEmptyCustomAppNameAsTheAppsOwnName() throws {
        try fixture.writeGroup(SubscriptionGroup(
            referenceName: "Pro",
            localizations: [
                "en-US": .init(name: "Pro", customAppName: ""),
                "de-DE": .init(name: "Pro")
            ]
        ))
        #expect(try groupProblems().isEmpty)
    }

    @Test func warnsAboutALanguageWithNoDisplayName() throws {
        try fixture.writeGroup(SubscriptionGroup(
            referenceName: "Pro",
            localizations: ["en-US": .init(name: "Pro")]
        ))

        let problems = try groupProblems()

        #expect(problems.map(\.kind) == [.groupTextNotTranslated])
        #expect(problems.first?.locale == "de-DE")
    }

    @Test func reportsAGroupFileThatCannotBeRead() throws {
        try fixture.writeRawGroup("{ not json", named: "Pro.json")
        #expect(try groupProblems().map(\.kind) == [.groupFileUnreadable])
    }

    // MARK: - Planning

    /// A draft by default, the same way a product's fixture carries one.
    func remote(
        version: RemoteProductVersion? = RemoteProductVersion(id: "v1", number: 3, state: .prepareForSubmission),
        localizations: [String: RemoteGroupLocalization] = [:]
    ) -> RemoteProducts {
        RemoteProducts(
            appID: "a1",
            products: [],
            groupNames: ["g1": "Pro"],
            groups: [RemoteSubscriptionGroup(
                id: "g1",
                referenceName: "Pro",
                version: version,
                localizations: localizations
            )]
        )
    }

    func catalog(status: AppInformation.Status = .approved) -> ProductCatalog {
        ProductCatalog(groups: ["Pro": SubscriptionGroup(
            referenceName: "Pro",
            status: status,
            localizations: [
                "en-US": .init(name: "Pro", customAppName: ""),
                "de-DE": .init(name: "Pro Abo")
            ]
        )])
    }

    @Test func plansTheWordsAGroupDoesNotHaveYet() {
        let outcome = ProductPlanner.plan(local: catalog(), config: config, remote: remote())

        #expect(outcome.groupTextChanges.map(\.id) == ["Pro|de-DE|name", "Pro|en-US|name"])
        #expect(outcome.groupTextChanges.allSatisfy { $0.action == .add })
        #expect(outcome.blocked.isEmpty)
    }

    @Test func plansOnlyTheWordsThatDiffer() {
        let outcome = ProductPlanner.plan(
            local: catalog(),
            config: config,
            remote: remote(localizations: [
                "en-US": RemoteGroupLocalization(id: "l1", locale: "en-US", name: "Pro"),
                "de-DE": RemoteGroupLocalization(id: "l2", locale: "de-DE", name: "Pro")
            ])
        )

        #expect(outcome.groupTextChanges.map(\.id) == ["Pro|de-DE|name"])
        #expect(outcome.groupTextChanges.first?.action == .change)
    }

    @Test func leavesOutAGroupNobodySignedOff() {
        let outcome = ProductPlanner.plan(local: catalog(status: .needsHuman), config: config, remote: remote())

        #expect(outcome.groupTextChanges.isEmpty)
        #expect(outcome.skipped.map(\.locale) == ["Pro"])
    }

    @Test func blocksAGroupTheStoreDoesNotHave() {
        let outcome = ProductPlanner.plan(
            local: catalog(),
            config: config,
            remote: RemoteProducts(appID: "a1", products: [], groupNames: [:])
        )

        #expect(outcome.groupTextChanges.isEmpty)
        #expect(outcome.blocked.map(\.parts) == [[.purchases]])
    }

    @Test func countsGroupWordsAsPurchaseWords() {
        let plan = ChangePlan(
            versionString: "1.0",
            versionState: nil,
            textChanges: [],
            missingLocales: [],
            screenshotPlans: [],
            groupTextChanges: ProductPlanner.plan(local: catalog(), config: config, remote: remote())
                .groupTextChanges,
            blocked: [],
            skipped: []
        )

        #expect(plan.changes(.purchases))
        #expect(plan.isEmpty == false)
        #expect(PushProgress.steps(for: .purchases, in: plan) == 2)
        #expect(ChangePlanFormatter.productWordLines(for: plan).contains("  Pro, de-DE"))
    }

    // MARK: - Pushing

    @Test func makesALanguageTheGroupDoesNotHave() async throws {
        let transport = StubTransport(.ok(#"{"data":{"type":"subscriptionGroupLocalizations","id":"l1"}}"#))
        let client = try ASCClient.stubbed(transport: transport)
        let plan = ChangePlan(
            versionString: "1.0",
            versionState: nil,
            textChanges: [],
            missingLocales: [],
            screenshotPlans: [],
            groupTextChanges: [.init(
                group: "Pro", locale: "en-US", field: .name,
                action: .add, oldValue: nil, newValue: "Pro"
            )],
            blocked: [],
            skipped: []
        )

        let result = await ProductPusher(client: client).pushText(plan, to: remote())

        #expect(result.written == ["Pro en-US"])
        let request = await transport.request(at: 0)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/v2/subscriptionGroupLocalizations")
        let body = try #require(request.httpBody.flatMap { String(data: $0, encoding: .utf8) })
        // The words hang off the draft, not off the group.
        #expect(body.contains(#""version""#))
        #expect(body.contains(#""subscriptionGroupVersions""#))
        #expect(body.contains(#""v1""#))
    }

    @Test func changesALanguageTheGroupAlreadyHas() async throws {
        let transport = StubTransport(.ok(#"{"data":{"type":"subscriptionGroupLocalizations","id":"l1"}}"#))
        let client = try ASCClient.stubbed(transport: transport)
        let plan = ChangePlan(
            versionString: "1.0",
            versionState: nil,
            textChanges: [],
            missingLocales: [],
            screenshotPlans: [],
            groupTextChanges: [.init(
                group: "Pro", locale: "en-US", field: .customAppName,
                action: .add, oldValue: nil, newValue: "My App"
            )],
            blocked: [],
            skipped: []
        )

        let result = await ProductPusher(client: client).pushText(
            plan,
            to: remote(localizations: [
                "en-US": RemoteGroupLocalization(id: "l1", locale: "en-US", name: "Pro")
            ])
        )

        #expect(result.isCompleteSuccess)
        let request = await transport.request(at: 0)
        #expect(request.httpMethod == "PATCH")
        #expect(request.url?.path == "/v2/subscriptionGroupLocalizations/l1")
    }

    // MARK: - Taking the store's words into files

    @Test func writesAGroupFileForAGroupWithWords() throws {
        let project = try fixture.load()
        let outcome = try ProductSnapshot.write(
            remote(localizations: [
                "en-US": RemoteGroupLocalization(id: "l1", locale: "en-US", name: "Pro"),
                "fr-FR": RemoteGroupLocalization(id: "l2", locale: "fr-FR", name: "Pro")
            ]),
            to: project
        )

        #expect(outcome.writtenGroups == ["Pro"])
        let group = try #require(ProductStore.load(in: project).groups["Pro"])
        #expect(group.status == .needsHuman)
        #expect(Array(group.localizations.keys) == ["en-US"])
    }

    @Test func writesNoFileForAGroupWithNoWords() throws {
        let outcome = try ProductSnapshot.write(remote(), to: fixture.load())
        #expect(outcome.writtenGroups.isEmpty)
    }
}
