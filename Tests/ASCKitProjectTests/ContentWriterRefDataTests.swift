import ASCKitAPI
import Foundation
import Testing
@testable import ASCKitProject

/// The writer refuses an image by the rules the validator checks it by.
struct ContentWriterRefDataTests {
    static func refData(
        width: Int, height: Int, alphaAllowed: Bool
    ) -> AssetLibraryRefData {
        AssetLibraryRefData(
            imageSpecs: [.init(
                specId: "s",
                dimensions: .init(minWidth: width, maxWidth: width, minHeight: height, maxHeight: height),
                alphaAllowed: alphaAllowed
            )],
            placementTypes: [
                .init(placementTypeId: .appScreenshot, acceptsAssetCategories: [.screenshotsAndPreviews], specMappings: [
                    .init(placementGroupId: DeviceClass.iPhone69.placementGroup, specs: ["s"])
                ])
            ]
        )
    }

    static func file(width: Int, height: Int, alpha: Bool = false) -> ScreenshotFile {
        ScreenshotFile(
            url: URL(fileURLWithPath: "/tmp/01-a.png"), fileName: "01-a.png", byteCount: 100,
            pixelWidth: width, pixelHeight: height, hasAlpha: alpha
        )
    }

    // MARK: - Alpha

    @Test func takesAnAlphaImageWhenTheReferenceDataAllowsAlpha() {
        let refData = Self.refData(width: 1290, height: 2796, alphaAllowed: true)
        let file = Self.file(width: 1290, height: 2796, alpha: true)

        #expect(ContentWriter.reasonToRefuse(file, for: .iPhone69, refData: refData) == nil)
        #expect(ContentWriter.onlyTheAlphaChannelRefuses(file, for: .iPhone69, refData: refData) == false)
    }

    @Test func refusesAnAlphaImageWhenTheReferenceDataDoesNot() {
        let refData = Self.refData(width: 1290, height: 2796, alphaAllowed: false)
        let file = Self.file(width: 1290, height: 2796, alpha: true)

        #expect(ContentWriter.reasonToRefuse(file, for: .iPhone69, refData: refData)?.contains("alpha channel") == true)
        #expect(ContentWriter.onlyTheAlphaChannelRefuses(file, for: .iPhone69, refData: refData))
    }

    // MARK: - Sizes

    @Test func takesTheSizeOfTheReferenceDataAndRefusesTheBuiltInOnly() {
        let refData = Self.refData(width: 1000, height: 2000, alphaAllowed: false)

        #expect(ContentWriter.reasonToRefuse(Self.file(width: 1000, height: 2000), for: .iPhone69, refData: refData) == nil)
        #expect(ContentWriter.reasonToRefuse(Self.file(width: 2000, height: 1000), for: .iPhone69, refData: refData) == nil)
        let reason = ContentWriter.reasonToRefuse(Self.file(width: 1290, height: 2796), for: .iPhone69, refData: refData)
        #expect(reason?.contains("1000x2000") == true)
        #expect(reason?.contains("iPhone 6.9 inch") == true)
    }

    // MARK: - No reference data

    @Test func keepsTheBuiltInRulesWithoutReferenceData() {
        let size = DeviceClass.iPhone69.acceptedSizes[0]

        #expect(ContentWriter.reasonToRefuse(Self.file(width: size.width, height: size.height), for: .iPhone69) == nil)
        #expect(ContentWriter.reasonToRefuse(Self.file(width: size.height, height: size.width), for: .iPhone69) == nil, "landscape")
        #expect(ContentWriter.reasonToRefuse(Self.file(width: 800, height: 600), for: .iPhone69)?.contains("800x600") == true)
        #expect(ContentWriter.reasonToRefuse(Self.file(width: size.width, height: size.height, alpha: true), for: .iPhone69)?
            .contains("alpha channel") == true)
        #expect(ContentWriter.onlyTheAlphaChannelRefuses(
            Self.file(width: size.width, height: size.height, alpha: true), for: .iPhone69
        ))
    }

    // MARK: - The inbox

    @Test func plansTheInboxWithTheKeptReferenceData() throws {
        let fixture = try FixtureProject()
        defer { fixture.remove() }
        try fixture.writeConfig(ProjectConfig(
            bundleID: "com.example.Demo", keyID: "ABC123", issuerID: "issuer",
            locales: ["en-US"], deviceClasses: [DeviceClass.iPhone69.id]
        ))
        let inbox = fixture.rootURL.appending(path: ProjectScaffold.inboxName)
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        try PNGWriter.write(to: inbox.appending(path: "01-a-iPhone-6.9-en_US.png"), width: 1000, height: 2000, hasAlpha: true)
        let project = try fixture.load()

        #expect(Inbox.plan(in: project).arrivals.isEmpty)

        try RefDataCache.save(Self.refData(width: 1000, height: 2000, alphaAllowed: true), in: project)
        #expect(Inbox.plan(in: project).arrivals.count == 1)
    }
}
