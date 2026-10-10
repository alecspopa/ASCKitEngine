import ASCKitTestSupport
import Foundation
import Testing
@testable import ASCKitAPI

struct ExperimentReaderTests {
    static let routes: [(String, StubTransport.Reply)] = [
        ("/appStoreVersionExperimentTreatmentLocalizations/tloc-en/placements", .ok("""
        {"data":[{"type":"appAssetLibraryPlacements","id":"p1","attributes":{
          "placementType":"APP_SCREENSHOT","placementGroup":"IPHONE_DYNAMIC_ISLAND_LARGE_PROFILE"},
          "relationships":{"image":{"data":{"type":"appAssetLibraryImages","id":"a1"}}}}],
         "included":[{"type":"appAssetLibraryImages","id":"a1","attributes":{"fileName":"01-a.png"}}]}
        """)),
        ("/appStoreVersionExperimentTreatmentLocalizations/tloc-de/placements", .ok(#"{"data":[]}"#)),
        ("/appStoreVersionExperimentTreatments/t1/appStoreVersionExperimentTreatmentLocalizations", .ok("""
        {"data":[
          {"type":"appStoreVersionExperimentTreatmentLocalizations","id":"tloc-en","attributes":{"locale":"en-US"}},
          {"type":"appStoreVersionExperimentTreatmentLocalizations","id":"tloc-de","attributes":{"locale":"de-DE"}}
        ]}
        """)),
        ("/v2/appStoreVersionExperiments/e1/appStoreVersionExperimentTreatments", .ok("""
        {"data":[{"type":"appStoreVersionExperimentTreatments","id":"t1","attributes":{"name":"Treatment A"}}]}
        """)),
        ("/apps/app1/appStoreVersionExperimentsV2", .ok("""
        {"data":[{"type":"appStoreVersionExperiments","id":"e1","attributes":{
          "name":"Bigger buttons","state":"PREPARE_FOR_SUBMISSION","platform":"IOS"}}]}
        """)),
        ("/v1/apps", .ok("""
        {"data":[{"type":"apps","id":"app1","attributes":{"bundleId":"com.example.Demo"}}]}
        """))
    ]

    @Test func readsADraftTestDownToItsPlacements() async throws {
        let transport = StubTransport(routes: Self.routes)
        let client = try ASCClient.stubbed(transport: transport)

        let remote = try await client.experiments(bundleID: "com.example.Demo")

        let experiment = try #require(remote.experiments.first)
        #expect(experiment.name == "Bigger buttons")
        #expect(experiment.isEditable)

        let treatment = try #require(experiment.treatments.first)
        #expect(treatment.name == "Treatment A")
        #expect(treatment.localizations.map(\.locale) == ["de-DE", "en-US"])
        #expect(treatment.localization("en-US")?.placements.map { $0.asset?.fileName } == ["01-a.png"])
        #expect(treatment.localization("de-DE")?.placements.isEmpty == true)
    }

    /// A finished test is not asked for, so a long history is not read. A
    /// test in review is, so a refusal can say why it takes no images.
    @Test func asksForEveryTestThatIsNotOver() async throws {
        let transport = StubTransport(routes: Self.routes)
        let client = try ASCClient.stubbed(transport: transport)

        _ = try await client.experiments(bundleID: "com.example.Demo")

        let urls = await transport.requests.compactMap(\.url?.absoluteString)
        let asked = try #require(urls.first { $0.contains("appStoreVersionExperimentsV2") })
        let query = try #require(URLComponents(string: asked)?.queryItems)
        let states = try #require(query.first { $0.name == "filter[state]" }?.value).split(separator: ",")
        #expect(states.contains("PREPARE_FOR_SUBMISSION"))
        #expect(states.contains("REJECTED"))
        #expect(states.contains("IN_REVIEW"))
        #expect(states.contains("COMPLETED") == false)
        #expect(states.contains("STOPPED") == false)
    }

    @Test func readsALockedTestAsLocked() async throws {
        let transport = StubTransport(routes: [
            ("/appStoreVersionExperimentTreatmentLocalizations/tloc-en/placements", .ok(#"{"data":[]}"#)),
            ("/appStoreVersionExperimentTreatments/t1/appStoreVersionExperimentTreatmentLocalizations", .ok("""
            {"data":[
              {"type":"appStoreVersionExperimentTreatmentLocalizations","id":"tloc-en","attributes":{"locale":"en-US"}}
            ]}
            """)),
            ("/v2/appStoreVersionExperiments/e1/appStoreVersionExperimentTreatments", .ok("""
            {"data":[{"type":"appStoreVersionExperimentTreatments","id":"t1","attributes":{"name":"Treatment A"}}]}
            """)),
            ("/apps/app1/appStoreVersionExperimentsV2", .ok("""
            {"data":[{"type":"appStoreVersionExperiments","id":"e1","attributes":{
              "name":"Bigger buttons","state":"IN_REVIEW","platform":"IOS"}}]}
            """)),
            ("/v1/apps", .ok("""
            {"data":[{"type":"apps","id":"app1","attributes":{"bundleId":"com.example.Demo"}}]}
            """))
        ])
        let client = try ASCClient.stubbed(transport: transport)

        let remote = try await client.experiments(bundleID: "com.example.Demo")

        let experiment = try #require(remote.experiments.first)
        #expect(experiment.state == .inReview)
        #expect(experiment.isEditable == false)
        #expect(experiment.treatments.first?.localizations.map(\.locale) == ["en-US"])
    }

    /// App Store Connect answered a finished test to the state filter, so the
    /// read leaves it out on its own.
    @Test func leavesOutAFinishedTestThatTheFilterLetThrough() async throws {
        var routes = Self.routes
        let list = try #require(routes.firstIndex { $0.0 == "/apps/app1/appStoreVersionExperimentsV2" })
        routes[list] = ("/apps/app1/appStoreVersionExperimentsV2", .ok("""
        {"data":[
          {"type":"appStoreVersionExperiments","id":"e1","attributes":{
            "name":"Bigger buttons","state":"PREPARE_FOR_SUBMISSION","platform":"IOS"}},
          {"type":"appStoreVersionExperiments","id":"e0","attributes":{
            "name":"Zoomed","state":"COMPLETED","platform":"IOS"}}
        ]}
        """))
        let transport = StubTransport(routes: routes)
        let client = try ASCClient.stubbed(transport: transport)

        let remote = try await client.experiments(bundleID: "com.example.Demo")

        #expect(remote.experiments.map(\.name) == ["Bigger buttons"])
    }

    @Test func aDraftAndARejectedTestAreEditable() {
        #expect(ExperimentState.prepareForSubmission.isEditable)
        #expect(ExperimentState.rejected.isEditable)
        #expect(ExperimentState.inReview.isEditable == false)
        #expect(ExperimentState.approved.isEditable == false)
        #expect(ExperimentState(rawValue: "SOMETHING_NEW").isEditable == false)
    }
}
