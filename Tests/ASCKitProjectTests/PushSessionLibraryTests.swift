import ASCKitAPI
import ASCKitTestSupport
import Foundation
import Testing
@testable import ASCKitProject

/// A project whose one screenshot App Store Connect already holds, in an old
/// set and as a placement of the same asset, the way it moved old uploads.
final class PushSessionLibraryTests {
    let fixture: FixtureProject

    init() throws {
        fixture = try FixtureProject()
        try fixture.writeConfig(ProjectConfig(
            bundleID: "com.example.Demo", keyID: "ABC123", issuerID: "issuer",
            sourceLocale: "en-US", locales: ["en-US"], deviceClasses: [DeviceClass.iPhone69.id]
        ))
        try fixture.writeCopy(AppInformation(locale: "en-US", status: .approved, fields: AppInformation.Fields(
            name: "Demo", subtitle: "The old subtitle", keywords: "household,restock",
            description: "Know what you have.", supportUrl: "https://example.com/support",
            privacyPolicyUrl: "https://example.com/privacy"
        )))
        try fixture.writeScreenshot(locale: "en-US", deviceClassID: DeviceClass.iPhone69.id,
                                    named: "01-a.png", width: 1320, height: 2868)
    }

    deinit {
        fixture.remove()
    }

    var localFile: URL {
        fixture.screenshotsDirectory(locale: "en-US", deviceClassID: DeviceClass.iPhone69.id).appending(path: "01-a.png")
    }

    func routes(oldChecksum: String, fileSize: Int, extraAssets: String = "") -> [(String, StubTransport.Reply)] {
        let image = """
        {"type":"appAssetLibraryImages","id":"asset1","attributes":{"fileName":"01-a.png","fileSize":\(fileSize),
          "state":"APPROVED","category":"APP_SCREENSHOTS_AND_PREVIEWS"}}
        """
        return [
            ("/placements", .ok("""
            {"data":[{"type":"appAssetLibraryPlacements","id":"p1","attributes":{
              "placementType":"APP_SCREENSHOT","placementGroup":"\(DeviceClass.iPhone69.placementGroup)"},
              "relationships":{"image":{"data":{"type":"appAssetLibraryImages","id":"asset1"}}}}],
             "included":[\(image)]}
            """)),
            ("/assetLibrary", .ok(#"{"data":{"type":"appAssetLibraries","id":"lib1"}}"#)),
            ("/appAssetLibraries/lib1/images", .ok("{\"data\":[\(image)\(extraAssets)]}")),
            ("/appAssetLibraries/lib1/videos", .ok(#"{"data":[]}"#)),
            ("/appAssetLibraryRefData", .ok(#"{"data":[]}"#)),
            ("/appScreenshotSets/set1/appScreenshots", .ok("""
            {"data":[{"type":"appScreenshots","id":"old1","attributes":{"fileName":"01-a.png",
              "fileSize":\(fileSize),"sourceFileChecksum":"\(oldChecksum)","assetDeliveryState":{"state":"COMPLETE"}}}]}
            """)),
            ("/appScreenshotSets", .ok("""
            {"data":[{"type":"appScreenshotSets","id":"set1","attributes":{"screenshotDisplayType":"APP_IPHONE_67"}}]}
            """)),
            ("/appInfoLocalizations", .ok(PushSessionTests.appInfoLocalizationsJSON)),
            ("/appStoreVersionLocalizations", .ok(PushSessionTests.versionLocalizationsJSON)),
            ("/appInfos", .ok(PushSessionTests.appInfosJSON)),
            ("/appStoreVersions", .ok(PushSessionTests.versionsJSON("1.0"))),
            ("/apps", .ok(PushSessionTests.appJSON))
        ]
    }

    func session(_ transport: StubTransport) throws -> PushSession {
        try PushSession(project: fixture.load(), client: ASCClient.stubbed(transport: transport))
    }

    @Test func learnsTheOldScreenshotsAndPlansNoUpload() async throws {
        let md5 = try FileChecksum.md5(of: localFile)
        let size = try Data(contentsOf: localFile).count
        let transport = StubTransport(routes: routes(oldChecksum: md5, fileSize: size))

        let reading = try await session(transport).read(includeProducts: false)

        #expect(reading.library?.libraryID == "lib1")
        #expect(reading.library?.record.assetID(md5: md5, fileSize: size) == "asset1")
        #expect(try AssetRecordStore.load(in: fixture.load()).assetID(md5: md5, fileSize: size) == "asset1")

        let plan = try #require(reading.changes)
        #expect(plan.screenshotPlans.first?.library != nil)
        #expect(plan.hasScreenshotChanges == false)
    }

    @Test func pushesNothingForAScreenshotTheLibraryAlreadyPlaces() async throws {
        let md5 = try FileChecksum.md5(of: localFile)
        let size = try Data(contentsOf: localFile).count
        let transport = StubTransport(routes: routes(oldChecksum: md5, fileSize: size))
        let session = try session(transport)
        let before = await transport.requestCount

        let outcome = try await session.pushImages(session.read(includeProducts: false))

        #expect(outcome.result.isCompleteSuccess)
        let writes = await transport.requests.dropFirst(before).filter { $0.httpMethod != "GET" }
        #expect(writes.isEmpty)
    }

    /// en-GB shows the en-US screenshots, so its own file goes to the Trash
    /// and nothing goes up for it.
    @Test func movesTheFilesOfALanguageThatShowsTheSourceToTheTrash() async throws {
        try fixture.writeConfig(ProjectConfig(
            bundleID: "com.example.Demo", keyID: "ABC123", issuerID: "issuer",
            sourceLocale: "en-US", locales: ["en-US", "en-GB"], deviceClasses: [DeviceClass.iPhone69.id],
            usesSourceScreenshots: ["en-GB": [DeviceClass.iPhone69.id]]
        ))
        try fixture.writeScreenshot(locale: "en-GB", deviceClassID: DeviceClass.iPhone69.id,
                                    named: "01-a.png", width: 1320, height: 2868)
        let british = fixture.screenshotsDirectory(locale: "en-GB", deviceClassID: DeviceClass.iPhone69.id)
            .appending(path: "01-a.png")
        let md5 = try FileChecksum.md5(of: localFile)
        let size = try Data(contentsOf: localFile).count
        let transport = StubTransport(routes: routes(oldChecksum: md5, fileSize: size))
        let session = try session(transport)
        let before = await transport.requestCount

        let outcome = try await session.pushImages(session.read(includeProducts: false))

        #expect(outcome.result.isCompleteSuccess)
        #expect(outcome.result.trashed == ["en-GB/01-a.png"])
        #expect(FileManager.default.fileExists(atPath: british.path) == false)
        #expect(FileManager.default.fileExists(atPath: localFile.path))
        let writes = await transport.requests.dropFirst(before).filter { $0.httpMethod != "GET" }
        #expect(writes.isEmpty)
    }

    @Test func replacesAPlacementWhoseFileChanged() async throws {
        let size = try Data(contentsOf: localFile).count
        let transport = StubTransport(routes: routes(oldChecksum: "an-older-export", fileSize: size))

        let reading = try await session(transport).read(includeProducts: false)

        let plan = try #require(reading.changes)
        #expect(plan.screenshotPlans.first?.action == .replace(removing: 1, adding: 1))
    }

    @Test func forgetsAnAssetTheLibraryNoLongerHas() async throws {
        let project = try fixture.load()
        var record = AssetRecord()
        record.record(md5: "deleted-on-the-website", AssetRecord.Entry(
            assetID: "gone", media: .image, fileName: "x.png", fileSize: 1
        ))
        try AssetRecordStore.save(record, in: project)
        let size = try Data(contentsOf: localFile).count
        let transport = StubTransport(routes: routes(oldChecksum: "x", fileSize: size))

        _ = try await session(transport).read(includeProducts: false)

        #expect(try AssetRecordStore.load(in: project).assets["deleted-on-the-website"] == nil)
    }

    @Test func refusesToReadOverADamagedRecord() async throws {
        let project = try fixture.load()
        try Data("{".utf8).write(to: AssetRecordStore.url(in: project))
        let transport = StubTransport(routes: routes(oldChecksum: "x", fileSize: 1))

        await #expect(throws: AssetRecordError.self) { try await self.session(transport).read(includeProducts: false) }
        #expect(try String(contentsOf: AssetRecordStore.url(in: project), encoding: .utf8) == "{")
    }

    @Test func keepsTheReferenceDataForTheNextCheck() async throws {
        let transport = StubTransport(routes: routes(oldChecksum: "x", fileSize: 1))
        _ = try await session(transport).read(includeProducts: false)
        #expect(try RefDataCache.load(in: fixture.load()) != nil)
    }

    @Test func refusesToReadTheImagesOfAnAppWithNoLibrary() async throws {
        var routes = routes(oldChecksum: "x", fileSize: 1)
        routes.insert(("/assetLibrary", .failure(404)), at: 0)

        await #expect(throws: LibraryReadError.noLibrary) {
            try await session(StubTransport(routes: routes)).read(includeProducts: false)
        }
    }

    @Test func readsTheWordsOfAnAppWithNoLibraryWhenTheImagesAreLeftOut() async throws {
        var routes = routes(oldChecksum: "x", fileSize: 1)
        routes.insert(("/assetLibrary", .failure(404)), at: 0)

        let reading = try await session(StubTransport(routes: routes)).read(includeScreenshots: false, includeProducts: false)
        #expect(reading.library == nil)
    }
}
