import ASCKitTestSupport
import Foundation
import Testing
@testable import ASCKitAPI

struct ListingPlacementTests {
    static let placements = """
    {"data":[\(LibraryJSON.placement("p1", assetID: "img1"))],
     "included":[\(LibraryJSON.image("img1", fileName: "01.png"))]}
    """

    @Test func readsThePlacementsOfEveryLanguageWithTheScreenshots() async throws {
        let transport = StubTransport(
            routes: [("/placements", .ok(Self.placements)), ("/appScreenshotSets", .ok(#"{"data":[]}"#))]
                + ListingReaderTests.routes()
        )
        let client = try ASCClient.stubbed(transport: transport)

        let listing = try await client.listing(bundleID: "com.example.Demo")

        #expect(listing.placements.map(\.locale) == ["de-DE", "en-US"])
        #expect(listing.placements.allSatisfy { $0.asset?.fileName == "01.png" })
        let paths = await transport.requests.compactMap(\.url?.path).filter { $0.hasSuffix("/placements") }
        #expect(paths.sorted() == [
            "/v1/appStoreVersionLocalizations/vloc-de/placements",
            "/v1/appStoreVersionLocalizations/vloc-en/placements"
        ])
    }

    @Test func readsNoPlacementsWithoutTheScreenshots() async throws {
        let transport = StubTransport(routes: [("/placements", .ok(Self.placements))] + ListingReaderTests.routes())
        let client = try ASCClient.stubbed(transport: transport)

        let listing = try await client.listing(bundleID: "com.example.Demo", includeScreenshots: false)

        #expect(listing.placements.isEmpty)
        let paths = await transport.requests.compactMap(\.url?.path)
        #expect(paths.contains { $0.hasSuffix("/placements") } == false)
    }
}
