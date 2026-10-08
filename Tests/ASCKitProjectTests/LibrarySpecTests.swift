import ASCKitAPI
import Foundation
import Testing
@testable import ASCKitProject

// MARK: - Device classes in the library

struct DeviceClassPlacementTests {
    @Test(arguments: DeviceClass.all)
    func putsEveryDeviceClassInAGroupOfItsOwn(deviceClass: DeviceClass) {
        let others = DeviceClass.all.filter { $0.id != deviceClass.id }
        #expect(deviceClass.placementGroup.hasSuffix("_PROFILE"))
        #expect(others.contains { $0.placementGroup == deviceClass.placementGroup } == false)
    }

    @Test func usesTheGroupsAppStoreConnectNamed() {
        #expect(DeviceClass.iPhone69.placementGroup == "IPHONE_DYNAMIC_ISLAND_LARGE_PROFILE")
        #expect(DeviceClass.iPad13.placementGroup == "IPAD_13_PROFILE")
        #expect(DeviceClass.mac.placementGroup == "MAC_PROFILE")
        #expect(DeviceClass.appleTV.placementGroup == "TV_PROFILE")
        #expect(DeviceClass.visionPro.placementGroup == "VISION_PRO_PROFILE")
        #expect(DeviceClass.watchUltra.placementGroup == "WATCH_ULTRA_PROFILE")
        #expect(DeviceClass.iMessageIPhone69.placementGroup == "IMESSAGE_IPHONE_DYNAMIC_ISLAND_LARGE_PROFILE")
        #expect(DeviceClass.iPhoneDuo.placementGroup == "IPHONE_DUO_PROFILE")
    }

    @Test func givesAnIMessageClassItsOwnPlacementType() {
        #expect(DeviceClass.iMessageIPad13.screenshotPlacementType == .iMessageAppScreenshot)
        #expect(DeviceClass.iPad13.screenshotPlacementType == .appScreenshot)
        #expect(DeviceClass.watchSeries10.screenshotPlacementType == .appScreenshot)
    }

    @Test func takesPreviewsOnlyWhereAppStoreConnectDoes() {
        let taking = DeviceClass.all.filter(\.takesPreviews).map(\.id)
        #expect(taking == [
            "iphone-6.9", "iphone-6.5", "iphone-6.1", "iphone-duo", "ipad-13", "ipad-11", "mac", "appletv", "visionpro"
        ])
    }

    @Test(arguments: [(1398, 2034), (2034, 1398), (2007, 2853), (2853, 2007)])
    func takesBothScreensOfTheIPhoneDuoEitherWayUp(width: Int, height: Int) {
        #expect(DeviceClass.iPhoneDuo.accepts(width: width, height: height))
    }

    @Test func leavesOtherSizesOutOfTheIPhoneDuo() {
        #expect(DeviceClass.iPhoneDuo.accepts(width: 1320, height: 2868) == false)
        #expect(DeviceClass.iPhoneDuo.displayName.contains("Duo"))
    }
}

// MARK: - The cache

struct RefDataCacheTests {
    let fixture: FixtureProject

    init() throws {
        fixture = try FixtureProject()
        try fixture.writeConfig(ProjectConfig(
            bundleID: "com.example.MyApp", keyID: "ABC123", issuerID: "issuer", locales: ["en-US"]
        ))
    }

    static let refData = AssetLibraryRefData(
        imageSpecs: [.init(specId: "s", dimensions: .init(minWidth: 1, maxWidth: 2, minHeight: 3, maxHeight: 4))]
    )

    @Test func keepsWhatItWasGiven() throws {
        defer { fixture.remove() }
        let project = try fixture.load()

        try RefDataCache.save(Self.refData, in: project)

        #expect(RefDataCache.load(in: project) == Self.refData)
        #expect(RefDataCache.url(in: project).path.contains("/cache/"))
    }

    @Test func readsNothingBeforeAnythingWasKept() throws {
        defer { fixture.remove() }
        #expect(try RefDataCache.load(in: fixture.load()) == nil)
    }

    @Test func readsNothingFromADamagedFile() throws {
        defer { fixture.remove() }
        let project = try fixture.load()
        let url = RefDataCache.url(in: project)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("{not json".utf8).write(to: url)

        #expect(RefDataCache.load(in: project) == nil)
    }

    @Test func checksWithTheKeptSizes() throws {
        defer { fixture.remove() }
        let project = try fixture.load()
        try RefDataCache.save(ValidatorSpecTests.refData, in: project)

        #expect(Validator(project: project).refData == ValidatorSpecTests.refData)
    }
}

// MARK: - Checking a file against the specs

struct ValidatorSpecTests {
    static let group = DeviceClass.iPhone69.placementGroup

    static let refData = AssetLibraryRefData(
        imageSpecs: [
            .init(
                specId: "big",
                dimensions: .init(minWidth: 1290, maxWidth: 1290, minHeight: 2796, maxHeight: 2796),
                alphaAllowed: false,
                fileExtensions: [".png", ".JPG"],
                maxFileSize: 1000
            ),
            .init(specId: "other", dimensions: .init(minWidth: 1, maxWidth: 1, minHeight: 1, maxHeight: 1))
        ],
        placementTypes: [
            .init(placementTypeId: .appScreenshot, acceptsAssetCategories: [.screenshotsAndPreviews], specMappings: [
                .init(placementGroupId: group, specs: ["big"])
            ])
        ]
    )

    static let config = ProjectConfig(
        bundleID: "com.example.MyApp", keyID: "ABC123", issuerID: "issuer", locales: ["en-US"]
    )

    func problems(
        _ name: String = "01-a.png",
        width: Int = 1290,
        height: Int = 2796,
        bytes: Int = 1000,
        alpha: Bool = false,
        refData: AssetLibraryRefData? = refData,
        deviceClass: DeviceClass = .iPhone69
    ) -> [Problem.Kind] {
        let file = ScreenshotFile(
            url: URL(fileURLWithPath: "/tmp/\(name)"), fileName: name, byteCount: bytes,
            pixelWidth: width, pixelHeight: height, hasAlpha: alpha
        )
        return Validator(config: Self.config, refData: refData)
            .validateFile(file, deviceClass: deviceClass, locale: "en-US", folder: "f")
            .map(\.kind)
    }

    @Test func takesAFileThatMatchesTheSpec() {
        #expect(problems().isEmpty)
        #expect(problems(width: 2796, height: 1290).isEmpty, "landscape")
    }

    @Test(arguments: [(1291, 2796), (1290, 2797), (1289, 2796)])
    func refusesAFileOnePixelOff(width: Int, height: Int) {
        #expect(problems(width: width, height: height) == [.screenshotWrongSize])
    }

    @Test func usesTheSpecInsteadOfTheBuiltInSizes() {
        // 1320x2868 is a built-in size for 6.9 inch, but not one this spec takes.
        #expect(problems(width: 1320, height: 2868) == [.screenshotWrongSize])
    }

    @Test func usesTheBuiltInSizesWithNoReferenceData() {
        #expect(problems(width: 1320, height: 2868, refData: nil).isEmpty)
        #expect(problems(width: 1290, height: 2797, refData: nil) == [.screenshotWrongSize])
    }

    @Test func usesTheBuiltInSizesForAGroupTheReferenceDataLacks() {
        #expect(problems(width: 2064, height: 2752, deviceClass: .iPad13).isEmpty)
        #expect(problems(width: 2064, height: 2752, refData: AssetLibraryRefData(), deviceClass: .iPad13).isEmpty)
    }

    @Test func refusesAlphaWhenTheSpecDoes() {
        #expect(problems(alpha: true) == [.screenshotHasAlpha])
    }

    @Test func takesAlphaWhenTheSpecAllowsIt() {
        var data = Self.refData
        data.imageSpecs[0].alphaAllowed = true
        #expect(problems(alpha: true, refData: data).isEmpty)
    }

    @Test func refusesAlphaWithNoReferenceData() {
        #expect(problems(alpha: true, refData: nil) == [.screenshotHasAlpha])
    }

    @Test func takesAFileOfExactlyTheLargestSize() {
        #expect(problems(bytes: 1000).isEmpty)
    }

    @Test func refusesAFileOneByteOver() {
        #expect(problems(bytes: 1001) == [.screenshotTooLarge])
    }

    @Test func checksNoFileSizeWithNoReferenceData() {
        #expect(problems(bytes: 50_000_000, refData: nil).isEmpty)
    }

    @Test(arguments: ["01-a.PNG", "01-a.jpg", "01-a.Jpg"])
    func readsTheFileTypeWhateverItsCase(name: String) {
        #expect(problems(name).isEmpty)
    }

    @Test(arguments: ["01-a.heic", "01-a", "01-a.png.gif"])
    func refusesAFileTypeTheSpecDoesNotName(name: String) {
        #expect(problems(name) == [.screenshotWrongFileType])
    }

    @Test func namesTheSizesOfARange() {
        let rules = ImageRules(sizes: [
            .init(minWidth: 1920, maxWidth: 3840, minHeight: 1280, maxHeight: 2560),
            .init(minWidth: 5244, maxWidth: 5244, minHeight: 2950, maxHeight: 2950)
        ])
        #expect(rules.sizeList.contains("1920x1280 to 3840x2560"))
        #expect(rules.sizeList.contains("5244x2950"))
    }

    @Test func takesAnyFileTypeWhenNoneIsNamed() {
        #expect(ImageRules(sizes: []).accepts(fileName: "x.webp"))
    }
}

// MARK: - iPhone Duo

struct IPhoneDuoTests {
    static func kinds(_ deviceClasses: [DeviceClass], platform: String? = nil) -> [Problem.Kind] {
        let config = ProjectConfig(
            bundleID: "com.example.MyApp", keyID: "K", issuerID: "I", locales: ["en-US"],
            deviceClasses: deviceClasses.map(\.id), platform: platform
        )
        return Validator(config: config).validateIPhoneDuo().map(\.kind)
    }

    @Test func warnsAnIPhoneAppWithNoIPhoneDuoScreenshots() {
        #expect(Self.kinds([.iPhone69]) == [.iPhoneDuoMissing])
        #expect(Self.kinds([.iPhone65, .iPad13]) == [.iPhoneDuoMissing])
    }

    @Test func saysNothingOnceTheProjectListsIt() {
        #expect(Self.kinds([.iPhone69, .iPhoneDuo]).isEmpty)
    }

    @Test(arguments: [[DeviceClass.iPad13], [.watchUltra], [.iMessageIPhone69], [.mac]])
    func saysNothingForAProjectWithNoIPhoneScreenshots(classes: [DeviceClass]) {
        #expect(Self.kinds(classes).isEmpty)
    }

    @Test func isAWarningThatNamesTheDeviceClassToAdd() throws {
        let config = ProjectConfig(bundleID: "b", keyID: "K", issuerID: "I", locales: ["en-US"],
                                   deviceClasses: [DeviceClass.iPhone69.id])
        let problem = try #require(Validator(config: config).validateIPhoneDuo().first)
        #expect(problem.severity == .warning)
        #expect(problem.fix?.english.contains("iphone-duo") == true)
        #expect(problem.message.english.contains("April 2027"))
    }

    @Test func readsTheIPhoneDuoOutOfAFileName() {
        #expect(DeviceClass.named("iphone-duo") == .iPhoneDuo)
        #expect(DeviceClass.iPhoneDuo.fileNameToken == "iPhone-Duo")
        #expect(DeviceClass.all(on: .ios).contains(.iPhoneDuo))
        #expect(DeviceClass.all(on: .macOS).contains(.iPhoneDuo) == false)
    }
}
