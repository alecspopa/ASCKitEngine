import ASCKitTestSupport
import Foundation
import Testing
@testable import ASCKitAPI

struct ListingReaderTests {
    // MARK: - Canned replies

    static let app = """
    {"data":[{"type":"apps","id":"app1",
      "attributes":{"name":"Demo","bundleId":"com.example.Demo"}}]}
    """

    static func versions(_ state: String, versionString: String = "1.0") -> String {
        """
        {"data":[{"type":"appStoreVersions","id":"v1",
          "attributes":{"versionString":"\(versionString)","appVersionState":"\(state)"}}]}
        """
    }

    static func appInfos(_ state: String) -> String {
        """
        {"data":[{"type":"appInfos","id":"info1","attributes":{"state":"\(state)"}}]}
        """
    }

    static let versionLocalizations = """
    {"data":[
      {"type":"appStoreVersionLocalizations","id":"vloc-en","attributes":{
        "locale":"en-US","description":"Know what you have.","keywords":"household,restock",
        "whatsNew":"First release.","supportUrl":"https://example.com/support"}},
      {"type":"appStoreVersionLocalizations","id":"vloc-de","attributes":{
        "locale":"de-DE","description":"Wissen, was da ist.","keywords":"haushalt",
        "promotionalText":""}}
    ]}
    """

    static let appInfoLocalizations = """
    {"data":[
      {"type":"appInfoLocalizations","id":"iloc-en","attributes":{
        "locale":"en-US","name":"Demo","subtitle":"Shared pantry list",
        "privacyPolicyUrl":"https://example.com/privacy"}},
      {"type":"appInfoLocalizations","id":"iloc-de","attributes":{
        "locale":"de-DE","name":"Demo","subtitle":"Geteilte Vorratsliste"}}
    ]}
    """

    /// Matched on the path rather than ordered, because the reader fetches the
    /// two kinds of localization at the same time. Ordered replies hand them out
    /// by whichever request happens to arrive first, which nothing decides.
    static func routes(
        versionState: String = "PREPARE_FOR_SUBMISSION",
        appInfoState: String = "PREPARE_FOR_SUBMISSION",
        versions versionsJSON: String? = nil
    ) -> [(String, StubTransport.Reply)] {
        [
            ("/appInfoLocalizations", .ok(appInfoLocalizations)),
            ("/appStoreVersionLocalizations", .ok(versionLocalizations)),
            ("/appInfos", .ok(appInfos(appInfoState))),
            ("/appStoreVersions", .ok(versionsJSON ?? versions(versionState))),
            ("/apps", .ok(app))
        ]
    }

    func makeListing(
        versionState: String = "PREPARE_FOR_SUBMISSION",
        appInfoState: String = "PREPARE_FOR_SUBMISSION"
    ) async throws -> RemoteListing {
        let transport = StubTransport(
            routes: Self.routes(versionState: versionState, appInfoState: appInfoState)
        )
        let client = try ASCClient.stubbed(transport: transport)
        return try await client.listing(bundleID: "com.example.Demo", includeScreenshots: false)
    }

    // MARK: - Tests

    @Test func readsTheAppAndTheVersion() async throws {
        let listing = try await makeListing()

        #expect(listing.appID == "app1")
        #expect(listing.appName == "Demo")
        #expect(listing.versionID == "v1")
        #expect(listing.versionString == "1.0")
        #expect(listing.versionState == .prepareForSubmission)
    }

    /// A Mac app has no IOS version. Asking for one read every macOS listing
    /// as an app with no versions at all, including one in front of the
    /// reviewer.
    @Test func readsAVersionOnWhicheverPlatformTheAppIsOn() async throws {
        let macVersion = """
        {"data":[{"type":"appStoreVersions","id":"v-mac","attributes":{
          "platform":"MAC_OS","versionString":"1.0","appVersionState":"PREPARE_FOR_SUBMISSION"}}]}
        """
        let transport = StubTransport(routes: Self.routes(versions: macVersion))
        let client = try ASCClient.stubbed(transport: transport)

        let listing = try await client.listing(bundleID: "com.example.Demo", includeScreenshots: false)
        #expect(listing.versionID == "v-mac")

        let asked = await transport.requests.compactMap(\.url?.absoluteString)
        #expect(asked.contains { $0.contains("appStoreVersions") && $0.contains("platform") } == false)
    }

    @Test func refusesABundleIdentifierNoAppMatches() async throws {
        let client = try ASCClient.stubbed(transport: StubTransport(.ok(#"{"data":[]}"#)))
        await #expect(throws: ListingError.self) {
            _ = try await client.listing(bundleID: "com.example.Missing")
        }
    }

    /// Name and subtitle come from the app information, everything else from
    /// the version. Getting that split wrong is a 409, not a bad value.
    @Test func readsNameAndSubtitleFromTheAppInformation() async throws {
        let listing = try await makeListing()
        let english = try #require(listing.appInfoLocalizations["en-US"])

        #expect(english.id == "iloc-en")
        #expect(english.values["name"] == "Demo")
        #expect(english.values["subtitle"] == "Shared pantry list")
        #expect(english.values["privacyPolicyUrl"] == "https://example.com/privacy")
    }

    @Test func readsTheRestFromTheVersion() async throws {
        let listing = try await makeListing()
        let english = try #require(listing.versionLocalizations["en-US"])

        #expect(english.id == "vloc-en")
        #expect(english.values["description"] == "Know what you have.")
        #expect(english.values["keywords"] == "household,restock")
        #expect(english.values["whatsNew"] == "First release.")
        #expect(english.values["supportUrl"] == "https://example.com/support")
    }

    /// This list is the authoritative answer to which codes App Store Connect
    /// accepts, which is why pull prints it.
    @Test func collectsEveryLanguageAcrossBothResources() async throws {
        #expect(try await makeListing().locales == ["de-DE", "en-US"])
    }

    @Test func saysWhenTheVersionAcceptsChanges() async throws {
        let listing = try await makeListing()
        #expect(listing.canEditText)
        #expect(listing.canEditScreenshots)
        #expect(listing.canEditNameAndSubtitle)
    }

    /// Waiting for Review takes some text edits and refuses screenshots.
    @Test func saysWhenScreenshotsAreRefusedButTextIsNot() async throws {
        let listing = try await makeListing(versionState: "WAITING_FOR_REVIEW")
        #expect(listing.canEditText)
        #expect(listing.canEditScreenshots == false)
    }

    @Test func saysWhenNothingCanBeChanged() async throws {
        let listing = try await makeListing(
            versionState: "READY_FOR_DISTRIBUTION",
            appInfoState: "READY_FOR_DISTRIBUTION"
        )
        #expect(listing.canEditText == false)
        #expect(listing.canEditNameAndSubtitle == false)
    }

    /// A version the developer pulled back takes a new name and subtitle.
    @Test(arguments: ["DEVELOPER_REJECTED", "REJECTED"])
    func takesANewNameOnARejectedVersion(state: String) async throws {
        let listing = try await makeListing(versionState: state, appInfoState: state)
        #expect(listing.canEditText)
        #expect(listing.canEditNameAndSubtitle)
    }

    /// A live app has no editable app information. The name is still read, so
    /// a plan compares against it and does not call every field new.
    @Test func readsALiveListingWithNoEditableAppInformation() async throws {
        let transport = StubTransport(
            routes: Self.routes(appInfoState: "READY_FOR_DISTRIBUTION")
        )
        let client = try ASCClient.stubbed(transport: transport)
        let listing = try await client.listing(bundleID: "com.example.Demo", includeScreenshots: false)

        #expect(listing.appInfoID == nil, "nothing may be written to the live app information")
        #expect(listing.appInfoLocalizations["en-US"]?.values["name"] == "Demo")
        #expect(listing.versionLocalizations.isEmpty == false)
    }

    @Test func readsTheAppInformationInReviewBeforeTheLiveOne() throws {
        let json = """
        {"data":[
          {"type":"appInfos","id":"old","attributes":{"state":"REPLACED_WITH_NEW_INFO"}},
          {"type":"appInfos","id":"live","attributes":{"state":"READY_FOR_DISTRIBUTION"}},
          {"type":"appInfos","id":"review","attributes":{"state":"WAITING_FOR_REVIEW"}}
        ]}
        """
        let infos = try JSONDecoder().decode(ListResponse<AppInfoAttributes>.self, from: Data(json.utf8)).data
        #expect(ASCClient.currentAppInfo(in: infos)?.id == "review")
        #expect(ASCClient.currentAppInfo(in: Array(infos.prefix(2)))?.id == "live")
    }

    @Test func skipsScreenshotsWhenAskedTo() async throws {
        let transport = StubTransport(routes: Self.routes())
        let client = try ASCClient.stubbed(transport: transport)

        let listing = try await client.listing(bundleID: "com.example.Demo", includeScreenshots: false)

        #expect(listing.screenshotSets.isEmpty)
        #expect(await transport.requestCount == 5, "no per-locale screenshot calls")
    }

    /// The version list used to be fetched twice when nothing was editable.
    @Test func asksForTheVersionListOnlyOnce() async throws {
        let transport = StubTransport(routes: Self.routes())
        let client = try ASCClient.stubbed(transport: transport)

        _ = try await client.listing(bundleID: "com.example.Demo", includeScreenshots: false)

        let versionCalls = await transport.requests.filter {
            $0.url?.path.hasSuffix("/appStoreVersions") == true
        }
        #expect(versionCalls.count == 1)
    }

    @Test func picksTheVersionStringItIsAskedFor() async throws {
        let twoVersions = """
        {"data":[
          {"type":"appStoreVersions","id":"live",
           "attributes":{"versionString":"1.0","appVersionState":"READY_FOR_DISTRIBUTION"}},
          {"type":"appStoreVersions","id":"next",
           "attributes":{"versionString":"1.1","appVersionState":"PREPARE_FOR_SUBMISSION"}}
        ]}
        """
        let transport = StubTransport(routes: Self.routes(versions: twoVersions))
        let client = try ASCClient.stubbed(transport: transport)

        let listing = try await client.listing(
            bundleID: "com.example.Demo",
            versionString: "1.0",
            includeScreenshots: false
        )
        #expect(listing.versionID == "live")
    }

    /// With no version named, the editable one is the useful answer even when
    /// a live version comes first in the list.
    @Test func prefersTheEditableVersionWhenNoneIsNamed() async throws {
        let twoVersions = """
        {"data":[
          {"type":"appStoreVersions","id":"live",
           "attributes":{"versionString":"1.0","appVersionState":"READY_FOR_DISTRIBUTION"}},
          {"type":"appStoreVersions","id":"next",
           "attributes":{"versionString":"1.1","appVersionState":"PREPARE_FOR_SUBMISSION"}}
        ]}
        """
        let transport = StubTransport(routes: Self.routes(versions: twoVersions))
        let client = try ASCClient.stubbed(transport: transport)

        let listing = try await client.listing(bundleID: "com.example.Demo", includeScreenshots: false)
        #expect(listing.versionID == "next")
    }

    // MARK: - The version on sale

    static let liveAndNext = """
    {"data":[
      {"type":"appStoreVersions","id":"live",
       "attributes":{"versionString":"1.0","appVersionState":"READY_FOR_DISTRIBUTION"}},
      {"type":"appStoreVersions","id":"next",
       "attributes":{"versionString":"1.1","appVersionState":"PREPARE_FOR_SUBMISSION"}}
    ]}
    """

    static let liveAndEditableInfos = """
    {"data":[
      {"type":"appInfos","id":"info-live","attributes":{"state":"READY_FOR_DISTRIBUTION"}},
      {"type":"appInfos","id":"info-next","attributes":{"state":"PREPARE_FOR_SUBMISSION"}}
    ]}
    """

    /// The version on sale and its app information answer with their own words.
    static let liveRoutes: [(String, StubTransport.Reply)] = [
        ("/appInfos/info-live/appInfoLocalizations", .ok("""
        {"data":[{"type":"appInfoLocalizations","id":"iloc-live","attributes":{
          "locale":"en-US","name":"Old Demo"}}]}
        """)),
        ("/appStoreVersions/live/appStoreVersionLocalizations", .ok("""
        {"data":[{"type":"appStoreVersionLocalizations","id":"vloc-live","attributes":{
          "locale":"en-US","description":"Old words."}}]}
        """))
    ]

    @Test func readsTheWordsOfTheVersionOnSaleWhenAsked() async throws {
        let transport = StubTransport(
            routes: Self.liveRoutes + [("/appInfos", .ok(Self.liveAndEditableInfos))]
                + Self.routes(versions: Self.liveAndNext)
        )
        let client = try ASCClient.stubbed(transport: transport)

        let listing = try await client.listing(
            bundleID: "com.example.Demo",
            includeScreenshots: false,
            includeLiveTexts: true
        )
        let live = try #require(listing.live)

        #expect(listing.versionID == "next")
        #expect(live.versionString == "1.0")
        #expect(live.appInfoLocalizations["en-US"]?.values["name"] == "Old Demo")
        #expect(live.versionLocalizations["en-US"]?.values["description"] == "Old words.")
        #expect(listing.versionLocalizations["en-US"]?.values["description"] == "Know what you have.")
    }

    @Test func readsNoWordsOfTheVersionOnSaleBeforeTheFirstRelease() async throws {
        let transport = StubTransport(routes: Self.routes())
        let client = try ASCClient.stubbed(transport: transport)

        let listing = try await client.listing(
            bundleID: "com.example.Demo",
            includeScreenshots: false,
            includeLiveTexts: true
        )
        let live = try #require(listing.live)

        #expect(live.versionString == nil)
        #expect(live.versionLocalizations.isEmpty)
        #expect(await transport.requestCount == 5, "nothing on sale, nothing more to ask")
    }

    @Test func leavesTheVersionOnSaleAloneUnlessAsked() async throws {
        let transport = StubTransport(routes: Self.routes(versions: Self.liveAndNext))
        let client = try ASCClient.stubbed(transport: transport)

        let listing = try await client.listing(bundleID: "com.example.Demo", includeScreenshots: false)

        #expect(listing.live == nil)
        #expect(await transport.requestCount == 5)
    }

    // MARK: - When one language fails

    /// One language refused used to take the others down with it, and what a
    /// person then read was "cancelled" from a sibling rather than the refusal.
    @Test func reportsTheRefusalRatherThanTheCancellationItCauses() async throws {
        let transport = OneBadLocaleTransport()
        let client = try ASCClient.stubbed(transport: transport, retryPolicy: .none)

        let thrown = await #expect(throws: (any Error).self) {
            _ = try await client.listing(bundleID: "com.example.Demo")
        }

        let error = try #require(thrown)
        #expect(error.isCancellation == false)
        #expect(error is ASCError)
        #expect(await transport.slowRequestFinished, "the other language was left to finish")
    }
}

/// German is refused at once. English takes long enough that the old code
/// cancelled it, and answers `URLError.cancelled` when it is, the way
/// URLSession does.
private actor OneBadLocaleTransport: Transport {
    private(set) var slowRequestFinished = false

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let path = request.url?.path ?? ""

        if path.contains("vloc-de/appScreenshotSets") {
            return try answer(status: 429, body: #"{"errors":[]}"#, to: request)
        }

        if path.contains("vloc-en/appScreenshotSets") {
            do {
                try await Task.sleep(for: .milliseconds(100))
            } catch {
                throw URLError(.cancelled)
            }
            slowRequestFinished = true
            return try answer(status: 200, body: #"{"data":[]}"#, to: request)
        }

        return try answer(status: 200, body: json(for: path), to: request)
    }

    private func json(for path: String) -> String {
        if path.contains("/appInfoLocalizations") { return ListingReaderTests.appInfoLocalizations }
        if path.contains("/appStoreVersionLocalizations") { return ListingReaderTests.versionLocalizations }
        if path.contains("/appInfos") { return ListingReaderTests.appInfos("PREPARE_FOR_SUBMISSION") }
        if path.contains("/appStoreVersions") { return ListingReaderTests.versions("PREPARE_FOR_SUBMISSION") }
        if path.contains("/apps") { return ListingReaderTests.app }
        return #"{"data":[]}"#
    }

    private func answer(
        status: Int,
        body: String,
        to request: URLRequest
    ) throws -> (Data, HTTPURLResponse) {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: [:]
        )!
        return (Data(body.utf8), response)
    }
}
