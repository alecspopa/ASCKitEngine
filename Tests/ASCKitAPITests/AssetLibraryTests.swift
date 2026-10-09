import ASCKitTestSupport
import Foundation
import Testing
@testable import ASCKitAPI

/// The bodies here are Apple's own examples from the App Asset Library
/// articles, so a request that matches them is one App Store Connect takes.
enum LibraryJSON {
    static func object(_ json: String) throws -> NSDictionary {
        try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? NSDictionary)
    }

    static func body(of request: URLRequest) throws -> NSDictionary {
        try #require(request.jsonObject() as NSDictionary?)
    }

    static func query(of request: URLRequest) -> [String: String] {
        let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { first, _ in first })
    }

    static func image(_ id: String, state: String = "PREPARE_FOR_SUBMISSION", fileName: String = "one.png") -> String {
        """
        {"type":"appAssetLibraryImages","id":"\(id)","attributes":{
          "category":"APP_SCREENSHOTS_AND_PREVIEWS","fileName":"\(fileName)","fileSize":14619,
          "state":"\(state)","specId":"f56c",
          "imageAsset":{"templateUrl":"https://is1.example.test/\(id)/{w}x{h}bb.{f}","width":1290,"height":2796}}}
        """
    }

    static func video(_ id: String, state: String = "PREPARE_FOR_SUBMISSION") -> String {
        """
        {"type":"appAssetLibraryVideos","id":"\(id)","attributes":{
          "category":"APP_SCREENSHOTS_AND_PREVIEWS","fileName":"preview.mp4","fileSize":31457280,
          "state":"\(state)","previewFrameTimeCode":"00:00:03:00",
          "previewFrameImage":{"state":"COMPLETE",
            "image":{"templateUrl":"https://is1.example.test/\(id)/{w}x{h}bb.{f}","width":1920,"height":886}}}}
        """
    }

    static func placement(
        _ id: String,
        type: String = "APP_SCREENSHOT",
        group: String = "IPHONE_DYNAMIC_ISLAND_LARGE_PROFILE",
        media: String = "image",
        assetID: String
    ) -> String {
        let assetType = media == "image" ? "appAssetLibraryImages" : "appAssetLibraryVideos"
        return """
        {"type":"appAssetLibraryPlacements","id":"\(id)","attributes":{
          "mediaType":"\(media.uppercased())","placementType":"\(type)","placementGroup":"\(group)",
          "state":"PARENT_PREPARE_FOR_SUBMISSION"},
         "relationships":{"\(media)":{"data":{"type":"\(assetType)","id":"\(assetID)"}}}}
        """
    }
}

// MARK: - The library and its assets

struct AssetLibraryTests {
    @Test func readsTheIDOfTheAppsLibrary() async throws {
        let transport = StubTransport(.ok(#"{"data":{"type":"appAssetLibraries","id":"lib1"}}"#))
        let client = try ASCClient.stubbed(transport: transport)

        #expect(try await client.assetLibraryID(appID: "app1") == "lib1")
        let request = await transport.request(at: 0)
        #expect(request.httpMethod == "GET")
        #expect(request.url?.path == "/v1/apps/app1/assetLibrary")
    }

    @Test func readsNoLibraryForAnAppThatHasNone() async throws {
        let transport = StubTransport([.failure(404), .failure(404)])
        let client = try ASCClient.stubbed(transport: transport)

        #expect(try await client.assetLibraryID(appID: "app1") == nil)
        #expect(try await client.readAssetLibrary(appID: "app1") == nil)
    }

    @Test func readsAnEmptyLibrary() async throws {
        let transport = StubTransport(routes: [
            ("/assetLibrary", .ok(#"{"data":{"type":"appAssetLibraries","id":"lib1"}}"#)),
            ("/images", .ok(#"{"data":[]}"#)),
            ("/videos", .ok(#"{"data":[]}"#))
        ])
        let client = try ASCClient.stubbed(transport: transport)

        let library = try #require(try await client.readAssetLibrary(appID: "app1"))
        #expect(library.id == "lib1")
        #expect(library.assets.isEmpty)
        #expect(library.placementIDs.isEmpty)
    }

    @Test func readsImagesAndVideosWithTheIDsOfTheirPlacements() async throws {
        let image = LibraryJSON.image("img1").replacingOccurrences(
            of: #""height":2796}}}"#,
            with: #""height":2796}},"relationships":{"placements":{"data":["#
                + #"{"type":"appAssetLibraryPlacements","id":"p1"},"#
                + #"{"type":"appAssetLibraryPlacements","id":"p2"}]}}}"#
        )
        let transport = StubTransport(routes: [
            ("/assetLibrary", .ok(#"{"data":{"type":"appAssetLibraries","id":"lib1"}}"#)),
            ("/images", .ok(#"{"data":[\#(image)]}"#)),
            ("/videos", .ok(#"{"data":[\#(LibraryJSON.video("vid1"))]}"#))
        ])
        let client = try ASCClient.stubbed(transport: transport)

        let library = try #require(try await client.readAssetLibrary(appID: "app1"))
        #expect(library.assets.map(\.id).sorted() == ["img1", "vid1"])
        #expect(library.placementIDs["img1"] == ["p1", "p2"])
        #expect(library.placementIDs["vid1"] == nil)

        let video = try #require(library.assets.first { $0.id == "vid1" })
        #expect(video.media == .video)
        #expect(video.previewFrameTimeCode == "00:00:03:00")
        #expect(video.preview?.width == 1920, "a video shows its poster frame")
    }

    @Test func listsAssetsWithTheirPlacementsAndFollowsEveryPage() async throws {
        let first = """
        {"data":[\(LibraryJSON.image("a"))],
         "links":{"next":"https://api.example.test/v1/appAssetLibraries/lib1/images?cursor=2"}}
        """
        let transport = StubTransport([.ok(first), .ok(#"{"data":[\#(LibraryJSON.image("b"))]}"#)])
        let client = try ASCClient.stubbed(transport: transport)

        let assets = try await client.libraryAssets(libraryID: "lib1", media: .image)

        #expect(assets.map(\.id) == ["a", "b"])
        let request = await transport.request(at: 0)
        #expect(request.url?.path == "/v1/appAssetLibraries/lib1/images")
        #expect(LibraryJSON.query(of: request)["include"] == "placements")
        #expect(LibraryJSON.query(of: request)["filter[id]"] == nil)
    }

    @Test func asksAboutManyAssetsInOneCall() async throws {
        let transport = StubTransport(.ok(#"{"data":[]}"#))
        let client = try ASCClient.stubbed(transport: transport)

        _ = try await client.libraryAssets(libraryID: "lib1", media: .video, ids: ["a", "b", "c"])

        let request = await transport.request(at: 0)
        #expect(request.url?.path == "/v1/appAssetLibraries/lib1/videos")
        #expect(LibraryJSON.query(of: request)["filter[id]"] == "a,b,c")
    }

    @Test func asksNothingForAnEmptyListOfIDs() async throws {
        let transport = StubTransport([])
        let client = try ASCClient.stubbed(transport: transport)

        #expect(try await client.libraryAssets(libraryID: "lib1", media: .image, ids: []).isEmpty)
        #expect(await transport.requestCount == 0)
    }

    @Test func reservesAnImageTheWayAppleShowsIt() async throws {
        let transport = StubTransport(.ok(#"{"data":\#(LibraryJSON.image("img1", state: "AWAITING_UPLOAD"))}"#))
        let client = try ASCClient.stubbed(transport: transport)

        _ = try await client.reserveLibraryAsset(
            media: .image,
            libraryID: "1234567890",
            category: .screenshotsAndPreviews,
            fileName: "ync-menu-6-9.png",
            fileSize: 14619,
            referenceName: "Menu screen",
            previewFrameTimeCode: "00:00:01:00"
        )

        let request = await transport.request(at: 0)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/v1/appAssetLibraryImages")
        #expect(try LibraryJSON.body(of: request) == LibraryJSON.object("""
        {"data":{"type":"appAssetLibraryImages",
          "attributes":{"fileName":"ync-menu-6-9.png","fileSize":14619,
            "category":"APP_SCREENSHOTS_AND_PREVIEWS","referenceName":"Menu screen"},
          "relationships":{"assetLibrary":{"data":{"type":"appAssetLibraries","id":"1234567890"}}}}}
        """), "an image never sends a time code")
    }

    @Test func reservesAVideoWithItsPosterFrame() async throws {
        let transport = StubTransport(.ok(#"{"data":\#(LibraryJSON.video("vid1", state: "AWAITING_UPLOAD"))}"#))
        let client = try ASCClient.stubbed(transport: transport)

        _ = try await client.reserveLibraryAsset(
            media: .video,
            libraryID: "1234567890",
            category: .screenshotsAndPreviews,
            fileName: "ync-preview.mp4",
            fileSize: 31_457_280,
            previewFrameTimeCode: "00:00:03:00"
        )

        let request = await transport.request(at: 0)
        #expect(request.url?.path == "/v1/appAssetLibraryVideos")
        #expect(try LibraryJSON.body(of: request) == LibraryJSON.object("""
        {"data":{"type":"appAssetLibraryVideos",
          "attributes":{"fileName":"ync-preview.mp4","fileSize":31457280,
            "category":"APP_SCREENSHOTS_AND_PREVIEWS","previewFrameTimeCode":"00:00:03:00"},
          "relationships":{"assetLibrary":{"data":{"type":"appAssetLibraries","id":"1234567890"}}}}}
        """))
    }

    @Test func reservesAVideoWithNoTimeCodeWhenNoneIsGiven() async throws {
        let transport = StubTransport(.ok(#"{"data":\#(LibraryJSON.video("vid1"))}"#))
        let client = try ASCClient.stubbed(transport: transport)

        _ = try await client.reserveLibraryAsset(
            media: .video, libraryID: "lib1", category: .creativeAssets, fileName: "header.mov", fileSize: 10
        )

        let attributes = try #require(
            await (LibraryJSON.body(of: transport.request(at: 0))["data"] as? NSDictionary)?["attributes"] as? NSDictionary
        )
        #expect(attributes["previewFrameTimeCode"] == nil)
        #expect(attributes["category"] as? String == "CREATIVE_ASSETS")
    }

    @Test func commitsWithUploadedAndNoChecksum() async throws {
        let transport = StubTransport(.ok(#"{"data":\#(LibraryJSON.image("img1", state: "UPLOAD_COMPLETE"))}"#))
        let client = try ASCClient.stubbed(transport: transport)

        _ = try await client.commitLibraryAsset(media: .image, id: "f400")

        let request = await transport.request(at: 0)
        #expect(request.httpMethod == "PATCH")
        #expect(request.url?.path == "/v1/appAssetLibraryImages/f400")
        #expect(try LibraryJSON.body(of: request) == LibraryJSON.object("""
        {"data":{"type":"appAssetLibraryImages","id":"f400","attributes":{"uploaded":true}}}
        """))
    }

    @Test func changesThePosterFrameOfAVideo() async throws {
        let transport = StubTransport(.ok(#"{"data":\#(LibraryJSON.video("c2d3"))}"#))
        let client = try ASCClient.stubbed(transport: transport)

        _ = try await client.setPreviewFrame(videoID: "c2d3", timeCode: "00:00:05:00")

        let request = await transport.request(at: 0)
        #expect(request.url?.path == "/v1/appAssetLibraryVideos/c2d3")
        #expect(try LibraryJSON.body(of: request) == LibraryJSON.object("""
        {"data":{"type":"appAssetLibraryVideos","id":"c2d3","attributes":{"previewFrameTimeCode":"00:00:05:00"}}}
        """))
    }

    @Test func renamesAndArchivesAnAsset() async throws {
        let transport = StubTransport([
            .ok(#"{"data":\#(LibraryJSON.image("f400"))}"#),
            .ok(#"{"data":\#(LibraryJSON.image("f400", state: "ARCHIVED"))}"#)
        ])
        let client = try ASCClient.stubbed(transport: transport)

        _ = try await client.renameLibraryAsset(media: .image, id: "f400", referenceName: "Menu screen (Fall 2026)")
        let archived = try await client.archiveLibraryAsset(media: .image, id: "f400")

        #expect(try await LibraryJSON.body(of: transport.request(at: 0)) == LibraryJSON.object("""
        {"data":{"type":"appAssetLibraryImages","id":"f400","attributes":{"referenceName":"Menu screen (Fall 2026)"}}}
        """))
        #expect(try await LibraryJSON.body(of: transport.request(at: 1)) == LibraryJSON.object("""
        {"data":{"type":"appAssetLibraryImages","id":"f400","attributes":{"archived":true}}}
        """))
        #expect(archived.attributes?.state == .archived)
    }

    @Test(arguments: LibraryMedia.allCases)
    func deletesAnAsset(media: LibraryMedia) async throws {
        let transport = StubTransport(StubTransport.Reply(status: 204, body: Data()))
        let client = try ASCClient.stubbed(transport: transport)

        try await client.deleteLibraryAsset(media: media, id: "a1")

        let request = await transport.request(at: 0)
        #expect(request.httpMethod == "DELETE")
        #expect(request.url?.path == "/v1/\(media.resourceType)/a1")
    }
}

// MARK: - Placements

struct PlacementTests {
    @Test func readsThePlacementsOfALanguageInTheStoresOrder() async throws {
        let json = """
        {"data":[
          \(LibraryJSON.placement("p2", assetID: "img2")),
          \(LibraryJSON.placement("p1", assetID: "img1")),
          \(LibraryJSON.placement("p3", type: "APP_PREVIEW", media: "video", assetID: "vid1"))],
         "included":[\(LibraryJSON.image("img1", fileName: "01.png")),
                     \(LibraryJSON.image("img2", fileName: "02.png")),
                     \(LibraryJSON.video("vid1"))]}
        """
        let transport = StubTransport(.ok(json))
        let client = try ASCClient.stubbed(transport: transport)

        let placements = try await client.readPlacements(on: .versionLocalization(id: "loc1"), locale: "en-US")

        #expect(placements.map(\.id) == ["p2", "p1", "p3"])
        #expect(placements.map { $0.asset?.fileName } == ["02.png", "01.png", "preview.mp4"])
        #expect(placements[2].type == .appPreview)
        #expect(placements[2].asset?.media == .video)
        #expect(placements.allSatisfy { $0.locale == "en-US" })

        let request = await transport.request(at: 0)
        #expect(request.url?.path == "/v1/appStoreVersionLocalizations/loc1/placements")
        let query = LibraryJSON.query(of: request)
        #expect(query["include"] == "image,video")
        #expect(query["sort"] == "placementGroupPosition")
    }

    @Test func readsTheTreatmentPathForATreatment() async throws {
        let transport = StubTransport(.ok(#"{"data":[]}"#))
        let client = try ASCClient.stubbed(transport: transport)

        _ = try await client.readPlacements(on: .treatmentLocalization(id: "t1"), locale: "de-DE")

        let path = await transport.request(at: 0).url?.path
        #expect(path == "/v1/appStoreVersionExperimentTreatmentLocalizations/t1/placements")
    }

    @Test func readsValuesThisBuildDoesNotKnow() async throws {
        let json = """
        {"data":[{"type":"appAssetLibraryPlacements","id":"p1","attributes":{
          "mediaType":"IMAGE","placementType":"HOLOGRAM_ASSET","placementGroup":"IPHONE_FOLD_PROFILE",
          "state":"PARENT_ON_HOLD"},
          "relationships":{"image":{"data":{"type":"appAssetLibraryImages","id":"img1"}}}}],
         "included":[\(LibraryJSON.image("img1", state: "QUARANTINED"))]}
        """
        let client = try ASCClient.stubbed(transport: StubTransport(.ok(json)))

        let placement = try #require(try await client.readPlacements(on: .versionLocalization(id: "l"), locale: "en-US").first)

        #expect(placement.type?.rawValue == "HOLOGRAM_ASSET")
        #expect(placement.group == "IPHONE_FOLD_PROFILE")
        #expect(placement.state?.rawValue == "PARENT_ON_HOLD")
        #expect(placement.asset?.state?.rawValue == "QUARANTINED")
    }

    @Test func keepsAPlacementWhoseAssetDidNotComeBack() async throws {
        let json = #"{"data":[\#(LibraryJSON.placement("p1", assetID: "gone"))]}"#
        let client = try ASCClient.stubbed(transport: StubTransport(.ok(json)))

        let placements = try await client.readPlacements(on: .versionLocalization(id: "l"), locale: "en-US")

        #expect(placements.map(\.id) == ["p1"])
        #expect(placements.first?.asset == nil)
    }

    @Test func readsManyLanguagesTogetherAndSortsThemByLanguage() async throws {
        let transport = StubTransport(routes: [
            ("/locDE/", .ok(#"{"data":[\#(LibraryJSON.placement("de1", assetID: "x"))]}"#)),
            ("/locEN/", .ok(#"{"data":[\#(LibraryJSON.placement("en2", assetID: "x")), \#(LibraryJSON.placement("en1", assetID: "y"))]}"#))
        ])
        let client = try ASCClient.stubbed(transport: transport)

        let placements = try await client.readPlacements([
            (.versionLocalization(id: "locEN"), "en-US"),
            (.versionLocalization(id: "locDE"), "de-DE")
        ])

        #expect(placements.map(\.id) == ["de1", "en2", "en1"])
    }

    @Test func placesAnImageOnAVersionTheWayAppleShowsIt() async throws {
        let transport = StubTransport(.ok(#"{"data":\#(LibraryJSON.placement("2e00", assetID: "f400"))}"#))
        let client = try ASCClient.stubbed(transport: transport)

        let created = try await client.createPlacement(
            type: .appScreenshot,
            group: "IPHONE_DYNAMIC_ISLAND_LARGE_PROFILE",
            media: .image,
            assetID: "f4000005",
            on: .versionLocalization(id: "b3a9")
        )

        #expect(created.id == "2e00")
        let request = await transport.request(at: 0)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/v1/appAssetLibraryPlacements")
        #expect(try LibraryJSON.body(of: request) == LibraryJSON.object("""
        {"data":{"type":"appAssetLibraryPlacements",
          "attributes":{"placementType":"APP_SCREENSHOT","placementGroup":"IPHONE_DYNAMIC_ISLAND_LARGE_PROFILE"},
          "relationships":{
            "image":{"data":{"type":"appAssetLibraryImages","id":"f4000005"}},
            "appStoreVersionLocalization":{"data":{"type":"appStoreVersionLocalizations","id":"b3a9"}}}}}
        """))
    }

    @Test func placesAVideoOnATreatment() async throws {
        let transport = StubTransport(.ok(#"{"data":\#(LibraryJSON.placement("p", media: "video", assetID: "v"))}"#))
        let client = try ASCClient.stubbed(transport: transport)

        _ = try await client.createPlacement(
            type: .appPreview, group: "MAC_PROFILE", media: .video, assetID: "c2d3",
            on: .treatmentLocalization(id: "t1")
        )

        #expect(try await LibraryJSON.body(of: transport.request(at: 0)) == LibraryJSON.object("""
        {"data":{"type":"appAssetLibraryPlacements",
          "attributes":{"placementType":"APP_PREVIEW","placementGroup":"MAC_PROFILE"},
          "relationships":{
            "video":{"data":{"type":"appAssetLibraryVideos","id":"c2d3"}},
            "appStoreVersionExperimentTreatmentLocalization":{"data":{
              "type":"appStoreVersionExperimentTreatmentLocalizations","id":"t1"}}}}}
        """))
    }

    @Test func deletesAPlacement() async throws {
        let transport = StubTransport(StubTransport.Reply(status: 204, body: Data()))
        let client = try ASCClient.stubbed(transport: transport)

        try await client.deletePlacement(id: "p1")

        let request = await transport.request(at: 0)
        #expect(request.httpMethod == "DELETE")
        #expect(request.url?.path == "/v1/appAssetLibraryPlacements/p1")
    }

    @Test func ordersAGroupTheWayAppleShowsIt() async throws {
        let transport = StubTransport(.ok(#"{"data":{"type":"appAssetLibraryPlacementOrderingRequests","id":"o1"}}"#))
        let client = try ASCClient.stubbed(transport: transport)

        try await client.orderPlacements(
            group: "IPHONE_DYNAMIC_ISLAND_LARGE_PROFILE",
            on: .versionLocalization(id: "b3a9"),
            orderedIDs: ["1e80", "2e00"]
        )

        let request = await transport.request(at: 0)
        #expect(request.url?.path == "/v1/appAssetLibraryPlacementOrderingRequests")
        #expect(try LibraryJSON.body(of: request) == LibraryJSON.object("""
        {"data":{"type":"appAssetLibraryPlacementOrderingRequests",
          "attributes":{"placementGroup":"IPHONE_DYNAMIC_ISLAND_LARGE_PROFILE"},
          "relationships":{
            "orderedPlacements":{"data":[
              {"type":"appAssetLibraryPlacements","id":"1e80"},
              {"type":"appAssetLibraryPlacements","id":"2e00"}]},
            "appStoreVersionLocalization":{"data":{"type":"appStoreVersionLocalizations","id":"b3a9"}}}}}
        """))
    }
}

// MARK: - Refusals

struct LibraryRefusalTests {
    static func conflict(_ code: String) -> ASCError {
        .conflict(details: [ASCErrorDetail(status: "409", code: code, detail: "words")])
    }

    @Test(arguments: [
        ("STATE_ERROR.ASSET_HAS_PLACEMENTS", LibraryRefusal.assetHasPlacements),
        ("STATE_ERROR.INVALID_ASSET_STATE", .assetStateForbids),
        ("STATE_ERROR.INVALID_STATE", .parentStateForbids),
        ("ENTITY_ERROR.ATTRIBUTE.INVALID", .placementNotSupported)
    ])
    func namesEachRefusalOfTheLibrary(code: String, refusal: LibraryRefusal) {
        #expect(LibraryRefusal(Self.conflict(code)) == refusal)
    }

    @Test func namesNoRefusalForAnotherError() {
        #expect(LibraryRefusal(Self.conflict("ENTITY_ERROR.NOT_FOUND")) == nil)
        #expect(LibraryRefusal(ASCError.forbidden(details: [])) == nil)
        #expect(LibraryRefusal(CancellationError()) == nil)
    }

    @Test func readsTheRefusalOutOfARealAnswer() async throws {
        let json = """
        {"errors":[{"status":"409","code":"STATE_ERROR.ASSET_HAS_PLACEMENTS",
          "title":"The request cannot be fulfilled because of the state of another resource.",
          "detail":"The asset cannot be deleted while placements still use it. Delete those placements first."}]}
        """
        let client = try ASCClient.stubbed(transport: StubTransport(.failure(409, json)))

        let error = await #expect(throws: ASCError.self) {
            try await client.deleteLibraryAsset(media: .image, id: "a1")
        }
        #expect(try LibraryRefusal(#require(error)) == .assetHasPlacements)
    }
}

// MARK: - States

struct LibraryAssetStateTests {
    @Test(arguments: [LibraryAssetState.awaitingUpload, .uploadComplete])
    func countsAnAssetOnItsWayInAsProcessing(state: LibraryAssetState) {
        #expect(state.isProcessing)
        #expect(state.canBePlaced == false)
    }

    @Test(arguments: [
        LibraryAssetState.complete, .prepareForSubmission, .readyForReview, .waitingForReview,
        .inReview, .accepted, .approved, .rejected
    ])
    func letsAProcessedAssetBePlaced(state: LibraryAssetState) {
        #expect(state.isProcessing == false)
        #expect(state.canBePlaced)
    }

    @Test(arguments: [LibraryAssetState.failed, .archived])
    func keepsAFailedOrArchivedAssetOffTheStore(state: LibraryAssetState) {
        #expect(state.canBePlaced == false)
    }
}
