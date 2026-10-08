import ASCKitAPI
import Foundation
import Testing
@testable import ASCKitProject

struct AssetRecordTests {
    let fixture: FixtureProject

    init() throws {
        fixture = try FixtureProject()
        try fixture.writeConfig(ProjectConfig(
            bundleID: "com.example.MyApp", keyID: "ABC123", issuerID: "issuer", locales: ["en-US"]
        ))
    }

    static func entry(_ id: String, name: String = "01-a.png", size: Int = 100) -> AssetRecord.Entry {
        AssetRecord.Entry(
            assetID: id, media: .image, category: .screenshotsAndPreviews, fileName: name, fileSize: size,
            uploadedAt: Date(timeIntervalSince1970: 1_790_000_000), state: .prepareForSubmission
        )
    }

    // MARK: - On disk

    @Test func readsBackWhatItWrote() throws {
        defer { fixture.remove() }
        let project = try fixture.load()
        var record = AssetRecord()
        record.record(md5: "ABC", Self.entry("a1"))
        record.record(md5: "def", Self.entry("a2", name: "02-b.png"))

        try AssetRecordStore.save(record, in: project)

        #expect(try AssetRecordStore.load(in: project) == record)
        #expect(AssetRecordStore.url(in: project).deletingLastPathComponent() == project.rootURL)
    }

    @Test func readsAnEmptyRecordWhenThereIsNoFile() throws {
        defer { fixture.remove() }
        #expect(try AssetRecordStore.load(in: fixture.load()).isEmpty)
    }

    @Test(arguments: ["", "  \n\t "])
    func readsAnEmptyRecordFromAnEmptyFile(contents: String) throws {
        defer { fixture.remove() }
        let project = try fixture.load()
        try Data(contents.utf8).write(to: AssetRecordStore.url(in: project))

        #expect(try AssetRecordStore.load(in: project).isEmpty)
    }

    @Test func refusesADamagedFileAndLeavesItAlone() throws {
        defer { fixture.remove() }
        let project = try fixture.load()
        let url = AssetRecordStore.url(in: project)
        try Data("{\"assets\": {".utf8).write(to: url)

        #expect(throws: AssetRecordError.damaged(path: url.path)) { try AssetRecordStore.load(in: project) }
        #expect(try String(contentsOf: url, encoding: .utf8) == "{\"assets\": {")
    }

    @Test func refusesAFileThatIsNotText() throws {
        defer { fixture.remove() }
        let project = try fixture.load()
        try Data([0xFF, 0xFE, 0x00, 0xC3]).write(to: AssetRecordStore.url(in: project))

        #expect(throws: AssetRecordError.self) { try AssetRecordStore.load(in: project) }
    }

    @Test func leavesTheOldFileWhenAWriteFails() throws {
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: fixture.rootURL.path)
            fixture.remove()
        }
        let project = try fixture.load()
        var first = AssetRecord()
        first.record(md5: "abc", Self.entry("a1"))
        try AssetRecordStore.save(first, in: project)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: fixture.rootURL.path)

        var second = first
        second.record(md5: "def", Self.entry("a2"))
        #expect(throws: (any Error).self) { try AssetRecordStore.save(second, in: project) }

        #expect(try AssetRecordStore.load(in: project) == first)
    }

    // MARK: - Lookups

    @Test func findsAnAssetByItsBytesAndSize() {
        var record = AssetRecord()
        record.record(md5: "ABC123", Self.entry("a1", size: 100))

        #expect(record.assetID(md5: "abc123", fileSize: 100) == "a1")
        #expect(record.assetID(md5: "ABC123", fileSize: 100) == "a1")
        #expect(record.assetID(md5: "other", fileSize: 100) == nil)
    }

    @Test func ignoresAnEntryWhoseSizeDoesNotMatch() {
        var record = AssetRecord()
        record.record(md5: "abc", Self.entry("a1", size: 100))
        #expect(record.assetID(md5: "abc", fileSize: 101) == nil)
    }

    @Test func keepsOneEntryForTwoFilesWithTheSameBytes() {
        var record = AssetRecord()
        record.record(md5: "abc", Self.entry("a1", name: "01-a.png"))
        record.record(md5: "abc", Self.entry("a1", name: "01-copy.png"))

        #expect(record.assets.count == 1)
        #expect(record.entry(forAssetID: "a1")?.md5 == "abc")
    }

    @Test func dropsWhatTheLibraryNoLongerHasAndKeepsTheRest() {
        var record = AssetRecord()
        record.record(md5: "a", Self.entry("kept"))
        record.record(md5: "b", Self.entry("gone"))
        let library = RemoteAssetLibrary(
            id: "lib",
            assets: [RemoteLibraryAsset(id: "kept", media: .image, state: .approved)],
            placementIDs: [:]
        )

        record.keepOnly(library)

        #expect(Array(record.assets.keys) == ["a"])
        #expect(record.assets["a"]?.state == .approved, "the state comes from App Store Connect")
    }

    @Test func keepsTheOldStateWhenTheLibraryNamesNone() {
        var record = AssetRecord()
        record.record(md5: "a", Self.entry("kept"))
        record.keepOnly(RemoteAssetLibrary(id: "lib", assets: [RemoteLibraryAsset(id: "kept", media: .image)], placementIDs: [:]))
        #expect(record.assets["a"]?.state == .prepareForSubmission)
    }

    @Test func dropsEverythingWhenTheLibraryIsEmpty() {
        var record = AssetRecord()
        record.record(md5: "a", Self.entry("x"))
        record.keepOnly(RemoteAssetLibrary(id: "lib", assets: [], placementIDs: [:]))
        #expect(record.isEmpty)
    }
}

// MARK: - From the old screenshot sets

struct AssetRecordAdoptionTests {
    static func shot(_ name: String, md5: String?, size: Int = 10) -> RemoteScreenshot {
        RemoteScreenshot(id: "old-\(name)", fileName: name, fileSize: size, sourceFileChecksum: md5)
    }

    static func placement(_ name: String, assetID: String, locale: String = "en-US",
                          group: String = DeviceClass.iPhone69.placementGroup,
                          type: PlacementType = .appScreenshot) -> RemotePlacement {
        RemotePlacement(
            id: "p-\(assetID)", locale: locale, type: type, group: group, state: .parentApproved,
            asset: RemoteLibraryAsset(id: assetID, media: .image, category: .screenshotsAndPreviews,
                                      fileName: name, fileSize: 20, state: .approved)
        )
    }

    static func set(_ shots: [RemoteScreenshot], locale: String = "en-US",
                    type: ScreenshotDisplayType = .appIPhone67) -> RemoteScreenshotSet {
        RemoteScreenshotSet(id: "set-\(locale)", locale: locale, displayType: type, screenshots: shots)
    }

    @Test func pairsEachOldScreenshotWithThePlacementInItsPlace() {
        var record = AssetRecord()
        record.adopt(
            sets: [Self.set([Self.shot("01.png", md5: "AAA"), Self.shot("02.png", md5: "bbb")])],
            placements: [Self.placement("01.png", assetID: "x1"), Self.placement("02.png", assetID: "x2")]
        )

        #expect(record.assets["aaa"]?.assetID == "x1")
        #expect(record.assets["bbb"]?.assetID == "x2")
        #expect(record.assets["aaa"]?.fileSize == 20, "the library's size, which is the one a lookup compares")
        #expect(record.assets["aaa"]?.state == .approved)
    }

    @Test func skipsAPairWhoseNamesDiffer() {
        var record = AssetRecord()
        record.adopt(
            sets: [Self.set([Self.shot("01.png", md5: "aaa"), Self.shot("02.png", md5: "bbb")])],
            placements: [Self.placement("02.png", assetID: "x2"), Self.placement("01.png", assetID: "x1")]
        )
        #expect(record.isEmpty)
    }

    @Test func skipsAScreenshotWithNoChecksum() {
        var record = AssetRecord()
        record.adopt(sets: [Self.set([Self.shot("01.png", md5: nil)])], placements: [Self.placement("01.png", assetID: "x1")])
        #expect(record.isEmpty)
    }

    @Test func pairsOnlyWithinTheSameLanguageGroupAndType() {
        var record = AssetRecord()
        record.adopt(
            sets: [Self.set([Self.shot("01.png", md5: "aaa")])],
            placements: [
                Self.placement("01.png", assetID: "de", locale: "de-DE"),
                Self.placement("01.png", assetID: "ipad", group: DeviceClass.iPad13.placementGroup),
                Self.placement("01.png", assetID: "msg", type: .iMessageAppScreenshot)
            ]
        )
        #expect(record.isEmpty)
    }

    @Test func pairsAnIMessageSetWithItsOwnType() {
        var record = AssetRecord()
        record.adopt(
            sets: [Self.set([Self.shot("01.png", md5: "aaa")], type: .iMessageIPhone67)],
            placements: [Self.placement("01.png", assetID: "msg", group: DeviceClass.iMessageIPhone69.placementGroup,
                                        type: .iMessageAppScreenshot)]
        )
        #expect(record.assets["aaa"]?.assetID == "msg")
    }

    @Test func stopsAtTheShorterOfTheTwo() {
        var record = AssetRecord()
        record.adopt(
            sets: [Self.set([Self.shot("01.png", md5: "aaa"), Self.shot("02.png", md5: "bbb")])],
            placements: [Self.placement("01.png", assetID: "x1")]
        )
        #expect(record.assets.keys.sorted() == ["aaa"])
    }

    @Test func leavesAnEntryThatIsAlreadyThere() {
        var record = AssetRecord()
        record.record(md5: "aaa", AssetRecordTests.entry("mine"))
        record.adopt(sets: [Self.set([Self.shot("01.png", md5: "aaa")])], placements: [Self.placement("01.png", assetID: "x1")])
        #expect(record.assets["aaa"]?.assetID == "mine")
    }

    @Test func skipsASetOfADisplayTypeNoDeviceClassUses() {
        var record = AssetRecord()
        record.adopt(
            sets: [Self.set([Self.shot("01.png", md5: "aaa")], type: .appIPhone58)],
            placements: [Self.placement("01.png", assetID: "x1")]
        )
        #expect(record.isEmpty)
    }
}
