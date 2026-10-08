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

        let remote = try await client.draftExperiments(bundleID: "com.example.Demo")

        let experiment = try #require(remote.experiments.first)
        #expect(experiment.name == "Bigger buttons")
        #expect(experiment.state?.isDraft == true)

        let treatment = try #require(experiment.treatments.first)
        #expect(treatment.name == "Treatment A")
        #expect(treatment.localizations.map(\.locale) == ["de-DE", "en-US"])
        #expect(treatment.localization("en-US")?.placements.map { $0.asset?.fileName } == ["01-a.png"])
        #expect(treatment.localization("de-DE")?.placements.isEmpty == true)
    }

    /// Only a draft is asked for. A test that was sent to review takes no
    /// images, so reading it would offer something a push cannot do.
    @Test func asksForDraftsOnly() async throws {
        let transport = StubTransport(routes: Self.routes)
        let client = try ASCClient.stubbed(transport: transport)

        _ = try await client.draftExperiments(bundleID: "com.example.Demo")

        let urls = await transport.requests.compactMap(\.url?.absoluteString)
        let asked = try #require(urls.first { $0.contains("appStoreVersionExperimentsV2") })
        #expect(asked.contains("filter%5Bstate%5D=PREPARE_FOR_SUBMISSION")
            || asked.contains("filter[state]=PREPARE_FOR_SUBMISSION"))
    }

    @Test func onlyTheFirstStateIsADraft() {
        #expect(ExperimentState.prepareForSubmission.isDraft)
        #expect(ExperimentState.inReview.isDraft == false)
        #expect(ExperimentState(rawValue: "SOMETHING_NEW").isDraft == false)
    }
}
