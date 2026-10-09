import ASCKitTestSupport
import Foundation
import Testing
@testable import ASCKitAPI

struct CustomPageReaderTests {
    static let routes: [(String, StubTransport.Reply)] = [
        ("/appCustomProductPageLocalizations/cloc-en/relationships/searchKeywords", .ok("""
        {"data":[{"type":"appKeywords","id":"moon"}]}
        """)),
        ("/appCustomProductPageLocalizations/cloc-de/relationships/searchKeywords", .ok(#"{"data":[]}"#)),
        ("/appCustomProductPageLocalizations/cloc-en/placements", .ok("""
        {"data":[{"type":"appAssetLibraryPlacements","id":"p1","attributes":{
          "placementType":"APP_SCREENSHOT","placementGroup":"IPHONE_DYNAMIC_ISLAND_LARGE_PROFILE"},
          "relationships":{"image":{"data":{"type":"appAssetLibraryImages","id":"a1"}}}}],
         "included":[{"type":"appAssetLibraryImages","id":"a1","attributes":{"fileName":"01-a.png"}}]}
        """)),
        ("/appCustomProductPageLocalizations/cloc-de/placements", .ok(#"{"data":[]}"#)),
        ("/appCustomProductPageVersions/v2/appCustomProductPageLocalizations", .ok("""
        {"data":[
          {"type":"appCustomProductPageLocalizations","id":"cloc-en","attributes":{
            "locale":"en-US","promotionalText":"See the moon."}},
          {"type":"appCustomProductPageLocalizations","id":"cloc-de","attributes":{"locale":"de-DE"}}
        ]}
        """)),
        ("/appCustomProductPages/page1/appCustomProductPageVersions", .ok("""
        {"data":[
          {"type":"appCustomProductPageVersions","id":"v1","attributes":{"version":"1","state":"APPROVED"}},
          {"type":"appCustomProductPageVersions","id":"v2","attributes":{
            "version":"2","state":"PREPARE_FOR_SUBMISSION","deepLink":"moondane://sky"}}
        ]}
        """)),
        ("/apps/app1/appCustomProductPages", .ok("""
        {"data":[{"type":"appCustomProductPages","id":"page1","attributes":{
          "name":"Night sky","url":"https://apps.apple.com/app/id1?ppid=page1","visible":true}}]}
        """)),
        ("/apps/app1/searchKeywords", .ok("""
        {"data":[{"type":"appKeywords","id":"moon"},{"type":"appKeywords","id":"stars"}]}
        """)),
        ("/v1/apps", .ok("""
        {"data":[{"type":"apps","id":"app1","attributes":{"bundleId":"com.example.Demo"}}]}
        """))
    ]

    @Test func readsAPageDownToItsKeywordsAndPlacements() async throws {
        let transport = StubTransport(routes: Self.routes)
        let client = try ASCClient.stubbed(transport: transport)

        let remote = try await client.customPages(bundleID: "com.example.Demo")

        let page = try #require(remote.pages.first)
        #expect(page.name == "Night sky")
        #expect(page.visible)
        #expect(page.isEditable)

        let version = try #require(page.version)
        #expect(version.id == "v2")
        #expect(version.deepLink == "moondane://sky")
        #expect(version.localizations.map(\.locale) == ["de-DE", "en-US"])

        let english = try #require(version.localization("en-US"))
        #expect(english.promotionalText == "See the moon.")
        #expect(english.keywordIDs == ["moon"])
        #expect(english.placements.map { $0.asset?.fileName } == ["01-a.png"])
        #expect(remote.keywords["en-US"] == ["moon", "stars"])
    }

    /// A draft shows before the approved version it replaces, because the
    /// draft is the one a person works on.
    @Test func showsTheDraftBeforeTheApprovedVersion() throws {
        let draft = try #require(CustomPageVersionState.prepareForSubmission.showOrder)
        let approved = try #require(CustomPageVersionState.approved.showOrder)
        #expect(draft < approved)
        #expect(CustomPageVersionState.replacedWithNewVersion.showOrder == nil)
    }

    @Test func onlyADraftTakesChanges() {
        #expect(CustomPageVersionState.prepareForSubmission.isEditable)
        #expect(CustomPageVersionState.approved.isEditable == false)
        #expect(CustomPageVersionState.rejected.isEditable == false)
        #expect(CustomPageVersionState(rawValue: "SOMETHING_NEW").isEditable == false)
    }

    @Test func linksAndUnlinksKeywordsWithTheRelationshipBody() async throws {
        let transport = StubTransport(routes: [("/relationships/searchKeywords", .ok(""))])
        let client = try ASCClient.stubbed(transport: transport)

        try await client.linkKeywords(["moon"], localizationID: "cloc-en")
        try await client.unlinkKeywords(["stars"], localizationID: "cloc-en")

        let requests = await transport.requests
        #expect(requests.map(\.httpMethod) == ["POST", "DELETE"])
        let body = try #require(await transport.bodyText(at: 0))
        #expect(body.contains(#""type":"appKeywords""#))
        #expect(body.contains(#""id":"moon""#))
    }

    @Test func writesOnlyThePromotionalText() async throws {
        let transport = StubTransport(routes: [("/appCustomProductPageLocalizations/cloc-en", .ok("""
        {"data":{"type":"appCustomProductPageLocalizations","id":"cloc-en","attributes":{"locale":"en-US"}}}
        """))])
        let client = try ASCClient.stubbed(transport: transport)

        try await client.updateCustomPageLocalization(id: "cloc-en", promotionalText: "New words.")

        let request = try #require(await transport.requests.first)
        #expect(request.httpMethod == "PATCH")
        let body = try #require(await transport.bodyText(at: 0))
        #expect(body.contains(#""promotionalText":"New words.""#))
        #expect(body.contains("locale") == false)
    }
}
