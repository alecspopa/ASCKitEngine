import ASCKitTestSupport
import Foundation
import Testing
@testable import ASCKitAPI

/// A cut of the reference data, with entries from Apple's examples.
enum RefDataJSON {
    static let attributes = """
    {"features":[{"featureId":"APP_STORE_VERSIONS","placementPolicies":[
        {"placementType":"APP_SCREENSHOT","groupLimits":[
          {"groupIds":["IPHONE_DYNAMIC_ISLAND_LARGE_PROFILE","MAC_PROFILE"],"maxCount":10}]},
        {"placementType":"APP_PREVIEW","groupLimits":[
          {"groupIds":["IPHONE_DYNAMIC_ISLAND_LARGE_PROFILE"],"maxCount":3}]}]},
      {"featureId":"PRODUCT_PAGE_OPTIMIZATIONS","placementPolicies":[
        {"placementType":"APP_SCREENSHOT","groupLimits":[
          {"groupIds":["IPHONE_DYNAMIC_ISLAND_LARGE_PROFILE"],"maxCount":8}]}]}],
     "placementProfileGroups":[
       {"placementProfileGroupId":"IPHONE_DYNAMIC_ISLAND_LARGE_PROFILE","platform":"IPHONE_APP_STORE",
        "displayClassId":"IPHONE_DYNAMIC_ISLAND_LARGE_DISPLAY"},
       {"placementProfileGroupId":"IPHONE_DUO_PROFILE","platform":"IPHONE_APP_STORE","displayClassId":"IPHONE_DUO"}],
     "imageSpecs":[{"specId":"f56c","shortName":"i1290x2796a0",
       "dimensions":{"minWidth":1290,"maxWidth":1290,"minHeight":2796,"maxHeight":2796},
       "aspectRatio":"6:13","compatiblePlacementTypes":["APP_SCREENSHOT","IMESSAGE_APP_SCREENSHOT"],
       "alphaAllowed":false,"fileExtensions":[".jpg",".jpeg",".png"],"maxFileSize":524288000,
       "mimeTypes":["image/jpeg","image/png"],"universalAsset":false}],
     "videoSpecs":[{"specId":"1861","shortName":"v1920x886f23~30t15~30u1",
       "dimensions":{"minWidth":1920,"maxWidth":1920,"minHeight":886,"maxHeight":886},
       "aspectRatio":"13:6","compatiblePlacementTypes":["APP_PREVIEW"],
       "frameRates":[{"minFps":23,"maxFps":30}],"duration":{"min":"PT15S","max":"PT30S"},
       "audioRequired":true,"fileExtensions":[".mp4",".m4v",".mov"],
       "mimeTypes":["video/quicktime","video/mp4","video/x-m4v"],"maxFileSize":524288000}],
     "placementTypes":[
       {"placementTypeId":"APP_SCREENSHOT","acceptsAssetCategories":["APP_SCREENSHOTS_AND_PREVIEWS"],
        "specMappings":[{"placementGroupId":"IPHONE_DYNAMIC_ISLAND_LARGE_PROFILE","specs":["f56c"]}]},
       {"placementTypeId":"APP_PREVIEW","acceptsAssetCategories":["APP_SCREENSHOTS_AND_PREVIEWS"],
        "specMappings":[{"placementGroupId":"IPHONE_DYNAMIC_ISLAND_LARGE_PROFILE","specs":["1861"]}]},
       {"placementTypeId":"PRODUCT_PAGE_HEADER_ASSET","acceptsAssetCategories":["CREATIVE_ASSETS"]}],
     "displayClasses":[{"displayClassId":"IPHONE_DUO","deviceFamily":"IPHONE",
       "screenDimensions":["1398x2034","2007x2853"]}]}
    """

    static let response = """
    {"data":[{"type":"appAssetLibraryRefData","id":"ref1","attributes":\(attributes)}]}
    """

    static func decoded() throws -> AssetLibraryRefData {
        try JSONDecoder().decode(AssetLibraryRefData.self, from: Data(attributes.utf8))
    }
}

struct AssetLibraryRefDataTests {
    @Test func readsTheReferenceDataFromItsAddress() async throws {
        let transport = StubTransport(.ok(RefDataJSON.response))
        let client = try ASCClient.stubbed(transport: transport)

        let data = try await client.assetLibraryRefData()

        #expect(await transport.request(at: 0).url?.path == "/v1/appAssetLibraryRefData")
        #expect(data.imageSpecs.map(\.specId) == ["f56c"])
        #expect(data.videoSpecs.first?.duration?.min == "PT15S")
        #expect(data.displayClasses.first?.screenDimensions == ["1398x2034", "2007x2853"])
    }

    @Test func readsEmptyReferenceDataWhenAppleSendsNone() async throws {
        let client = try ASCClient.stubbed(transport: StubTransport(.ok(#"{"data":[]}"#)))
        #expect(try await client.assetLibraryRefData() == AssetLibraryRefData())
    }

    @Test func readsAnArrayAppleLeftOutAsEmpty() throws {
        let data = try JSONDecoder().decode(AssetLibraryRefData.self, from: Data(#"{"imageSpecs":[]}"#.utf8))
        #expect(data.features.isEmpty)
        #expect(data.videoSpecs.isEmpty)
    }

    @Test func keepsEverythingThroughAWriteAndARead() throws {
        let data = try RefDataJSON.decoded()
        let again = try JSONDecoder().decode(AssetLibraryRefData.self, from: JSONEncoder().encode(data))
        #expect(again == data)
    }

    @Test func findsTheMostAGroupHoldsForEachFeature() throws {
        let data = try RefDataJSON.decoded()
        let group = "IPHONE_DYNAMIC_ISLAND_LARGE_PROFILE"

        #expect(data.maximumCount(feature: "APP_STORE_VERSIONS", type: .appScreenshot, group: group) == 10)
        #expect(data.maximumCount(feature: "APP_STORE_VERSIONS", type: .appPreview, group: group) == 3)
        #expect(data.maximumCount(feature: "PRODUCT_PAGE_OPTIMIZATIONS", type: .appScreenshot, group: group) == 8)
        #expect(data.maximumCount(feature: "APP_STORE_VERSIONS", type: .appScreenshot, group: "MAC_PROFILE") == 10)
    }

    @Test func namesNoLimitWhereAppleNamesNone() throws {
        let data = try RefDataJSON.decoded()
        #expect(data.maximumCount(feature: "IN_APP_EVENTS", type: .appScreenshot, group: "MAC_PROFILE") == nil)
        #expect(data.maximumCount(feature: "APP_STORE_VERSIONS", type: .productPageHeader, group: "X") == nil)
        #expect(data.maximumCount(feature: "APP_STORE_VERSIONS", type: .appPreview, group: "MAC_PROFILE") == nil)
    }

    @Test func findsTheSpecsOfAGroup() throws {
        let data = try RefDataJSON.decoded()
        let group = "IPHONE_DYNAMIC_ISLAND_LARGE_PROFILE"

        #expect(data.imageSpecs(type: .appScreenshot, group: group).map(\.specId) == ["f56c"])
        #expect(data.videoSpecs(type: .appPreview, group: group).map(\.specId) == ["1861"])
        #expect(data.imageSpecs(type: .appPreview, group: group).isEmpty)
        #expect(data.specIDs(type: .appScreenshot, group: "UNKNOWN_PROFILE").isEmpty)
    }

    @Test func findsTheCategoryAPlacementTypeTakes() throws {
        let data = try RefDataJSON.decoded()
        #expect(data.category(for: .appScreenshot) == .screenshotsAndPreviews)
        #expect(data.category(for: .productPageHeader) == .creativeAssets)
        #expect(data.category(for: .searchResults) == nil)
    }

    @Test func findsTheDisplayClassOfAGroup() throws {
        let data = try RefDataJSON.decoded()
        #expect(data.profileGroup("IPHONE_DUO_PROFILE")?.displayClassId == "IPHONE_DUO")
        #expect(data.profileGroup("NOT_A_PROFILE") == nil)
    }

    @Test(arguments: [
        (1290, 2796, true), (2796, 1290, true), (1291, 2796, false), (1290, 2795, false)
    ])
    func fitsAnExactSizeEitherWayUp(width: Int, height: Int, fits: Bool) {
        let exact = AssetLibraryRefData.Dimensions(minWidth: 1290, maxWidth: 1290, minHeight: 2796, maxHeight: 2796)
        #expect(exact.fits(width: width, height: height) == fits)
    }

    @Test(arguments: [
        (1920, 1280, true), (3840, 2560, true), (2400, 1600, true), (1919, 1280, false), (3841, 2560, false)
    ])
    func fitsARangeOfSizes(width: Int, height: Int, fits: Bool) {
        let range = AssetLibraryRefData.Dimensions(minWidth: 1920, maxWidth: 3840, minHeight: 1280, maxHeight: 2560)
        #expect(range.fits(width: width, height: height) == fits)
    }
}
