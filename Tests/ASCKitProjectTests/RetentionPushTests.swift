import ASCKitAPI
import ASCKitTestSupport
import Foundation
import Testing
@testable import ASCKitProject

struct RetentionPushTests {
    let config = ProjectConfig(bundleID: "com.example.MyApp", keyID: "ABC123", locales: ["en-US", "de-DE"])

    func local(_ words: [String: RetentionMessage.Localization], status: AppInformation.Status = .approved) -> ProductCatalog {
        ProductCatalog(retentionMessages: [
            "Cancel": RetentionMessage(referenceName: "Cancel", status: status, localizations: words)
        ])
    }

    func remote(state: RetentionVersionState = .prepareForSubmission, words: [String: RemoteRetentionWords] = [
        "en-US": RemoteRetentionWords(id: "w1", header: "Stay", body: "More soon")
    ]) -> RemoteProducts {
        RemoteProducts(
            appID: "app", products: [], groupNames: [:],
            retentionMessages: [RemoteRetentionMessage(
                id: "m1", referenceName: "Cancel",
                version: RemoteRetentionVersion(id: "v1", state: state, words: words, placementID: nil)
            )]
        )
    }

    func plan(_ local: ProductCatalog, _ remote: RemoteProducts) -> ProductPlanner.Outcome {
        ProductPlanner.plan(local: local, config: config, remote: remote)
    }

    // MARK: - Plan

    @Test func plansAChangeAndAnAdd() {
        let outcome = plan(local([
            "en-US": .init(header: "Stay", body: "New things soon"),
            "de-DE": .init(header: "Bleib", body: "Bald mehr")
        ]), remote())

        let changes = outcome.retentionTextChanges
        #expect(changes.map(\.id) == ["Cancel|de-DE|header", "Cancel|de-DE|body", "Cancel|en-US|body"])
        #expect(changes.last?.action == .change)
        #expect(changes.last?.oldValue == "More soon")
        #expect(changes.first?.action == .add)
    }

    @Test func plansNothingWhenTheWordsMatch() {
        let outcome = plan(local(["en-US": .init(header: "Stay", body: "More soon")]), remote())
        #expect(outcome.retentionTextChanges.isEmpty)
        #expect(outcome.blocked.isEmpty)
    }

    @Test func leavesAPublishedMessageAlone() {
        let outcome = plan(local(["en-US": .init(header: "Go", body: "More soon")]), remote(state: .approved))
        #expect(outcome.retentionTextChanges.isEmpty)
        #expect(outcome.blocked.count == 1)
        #expect(outcome.blocked.first?.parts == [.purchases])
    }

    @Test func neverMakesAMessage() {
        let outcome = plan(
            local(["en-US": .init(header: "Go", body: "b")]),
            RemoteProducts(appID: "app", products: [], groupNames: [:])
        )
        #expect(outcome.retentionTextChanges.isEmpty)
        #expect(outcome.blocked.count == 1)
    }

    @Test func skipsAMessageNotReadyToPublish() {
        let outcome = plan(local(["en-US": .init(header: "Go", body: "b")], status: .draft), remote())
        #expect(outcome.retentionTextChanges.isEmpty)
        #expect(outcome.skipped.map(\.locale) == ["Cancel"])
    }

    @Test func aRetentionChangeMovesTheDigest() {
        let empty = ChangePlan(versionString: "1.0", versionState: nil, textChanges: [], missingLocales: [],
                               screenshotPlans: [], blocked: [], skipped: [])
        let changed = ChangePlan(
            versionString: "1.0", versionState: nil, textChanges: [], missingLocales: [], screenshotPlans: [],
            retentionTextChanges: [.init(message: "Cancel", locale: "en-US", field: .body,
                                         action: .change, oldValue: "a", newValue: "b")],
            blocked: [], skipped: []
        )
        #expect(empty.digest != changed.digest)
        #expect(changed.changes(.purchases))
    }

    // MARK: - Push

    func push(_ outcome: ProductPlanner.Outcome, remote: RemoteProducts, dryRun: Bool = false)
        async throws -> (ProductPusher.TextResult, StubTransport) {
        let transport = StubTransport(routes: [
            ("/retentionMessageLocalizations", .ok(#"{"data":{"type":"retentionMessageLocalizations","id":"w9"}}"#))
        ])
        let plan = ChangePlan(
            versionString: "1.0", versionState: nil, textChanges: [], missingLocales: [], screenshotPlans: [],
            retentionTextChanges: outcome.retentionTextChanges, blocked: [], skipped: []
        )
        let result = try await ProductPusher(client: ASCClient.stubbed(transport: transport))
            .pushText(plan, to: remote, dryRun: dryRun)
        return (result, transport)
    }

    @Test func changesAnExistingLanguageAndAddsANewOne() async throws {
        let remote = remote()
        let outcome = plan(local([
            "en-US": .init(header: "Stay", body: "New things soon"),
            "de-DE": .init(header: "Bleib", body: "Bald mehr")
        ]), remote)

        let (result, transport) = try await push(outcome, remote: remote)
        #expect(result.failed.isEmpty)
        #expect(result.written == ["Cancel de-DE", "Cancel en-US"])

        let create = await transport.request(at: 0)
        #expect(create.httpMethod == "POST")
        let created = try #require(create.jsonObject()?["data"] as? [String: Any])
        #expect((created["attributes"] as? [String: Any])?["locale"] as? String == "de-DE")

        let change = await transport.request(at: 1)
        #expect(change.url?.path == "/v1/retentionMessageLocalizations/w1")
        let changed = try #require(change.jsonObject()?["data"] as? [String: Any])
        #expect((changed["attributes"] as? [String: Any])?.keys.sorted() == ["body"])
    }

    @Test func aDryRunSendsNothing() async throws {
        let remote = remote()
        let outcome = plan(local(["en-US": .init(header: "Stay", body: "New")]), remote)
        let (result, transport) = try await push(outcome, remote: remote, dryRun: true)
        #expect(result.wouldSend.count == 1)
        #expect(await transport.requestCount == 0)
    }
}
