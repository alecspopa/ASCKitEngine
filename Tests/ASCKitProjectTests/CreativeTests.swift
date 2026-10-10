import ASCKitAPI
import ASCKitTestSupport
import Foundation
import Testing
@testable import ASCKitProject

enum Art {
    static func image(_ name: String, _ width: Int, _ height: Int, alpha: Bool = false) -> CreativeFile {
        CreativeFile(url: URL(fileURLWithPath: "/tmp/\(name)"), fileName: name, byteCount: 100, media: .image,
                     pixelWidth: width, pixelHeight: height, hasAlpha: alpha, duration: nil, frameRate: nil)
    }

    static func video(_ name: String, _ width: Int, _ height: Int, seconds: Double = 10, fps: Double = 30) -> CreativeFile {
        CreativeFile(url: URL(fileURLWithPath: "/tmp/\(name)"), fileName: name, byteCount: 100, media: .video,
                     pixelWidth: width, pixelHeight: height, hasAlpha: nil, duration: seconds, frameRate: fps)
    }

    static func folder(_ files: [CreativeRole: [CreativeFile]], strays: [String] = []) -> CreativeFolder {
        var folder = CreativeFolder()
        folder.files["en-US"] = files
        if strays.isEmpty == false { folder.strays["en-US"] = strays }
        return folder
    }
}

struct ValidatorCreativeTests {
    func kinds(_ folder: CreativeFolder) -> [Problem.Kind] {
        let config = ProjectConfig(bundleID: "b", keyID: "K", issuerID: "I", locales: ["en-US"])
        return Validator(config: config).validateCreativeFolder(folder, root: "c").map(\.kind)
    }

    /// The problems of one header, beside a search results file so that the
    /// header goes into no other place.
    func headerKinds(_ header: CreativeFile) -> [Problem.Kind] {
        kinds(Art.folder([.header: [header], .searchResults: [Art.image("search-results.png", 1920, 1280)]]))
    }

    @Test(arguments: [("header.png", 3840, 1646), ("header.jpg", 3840, 1646), ("header.png", 5244, 2950)])
    func takesTheHeaderSizes(name: String, width: Int, height: Int) {
        #expect(headerKinds(Art.image(name, width, height)).isEmpty)
    }

    @Test func refusesTheWideHeaderAsAJpeg() {
        #expect(headerKinds(Art.image("header.jpg", 5244, 2950)) == [.creativeWrongSize])
    }

    @Test(arguments: [(1920, 1280, true), (3840, 2560, true), (2400, 1600, true), (2400, 1601, false),
                      (1800, 1200, false), (5244, 2950, true)])
    func takesSearchResultsAtThreeByTwo(width: Int, height: Int, accepted: Bool) {
        let kinds = kinds(Art.folder([.searchResults: [Art.image("search-results.png", width, height)]]))
        #expect(kinds == (accepted ? [] : [.creativeWrongSize]))
    }

    @Test func refusesAlpha() {
        #expect(headerKinds(Art.image("header.png", 3840, 1646, alpha: true)) == [.creativeHasAlpha])
    }

    @Test(arguments: [(4.9, false), (5.0, true), (30.0, true), (30.5, false)])
    func checksTheLengthOfAVideo(seconds: Double, accepted: Bool) {
        let kinds = headerKinds(Art.video("header.mov", 3840, 1646, seconds: seconds))
        #expect(kinds == (accepted ? [] : [.creativeWrongLength]))
    }

    @Test(arguments: [(25.0, false), (30.0, true), (60.0, true), (48.0, false)])
    func takesThirtyOrSixtyFramesASecond(fps: Double, accepted: Bool) {
        let kinds = headerKinds(Art.video("header.mov", 3840, 1646, fps: fps))
        #expect(kinds == (accepted ? [] : [.creativeWrongFrameRate]))
    }

    @Test func refusesTwoFilesForOneRole() {
        let folder = Art.folder([.header: [Art.image("header.png", 3840, 1646), Art.video("header.mov", 3840, 1646)],
                                 .searchResults: [Art.image("search-results.png", 1920, 1280)]])
        #expect(kinds(folder) == [.creativeTwoFiles])
    }

    @Test func reportsASourceCreativeNameThePushCannotUse() {
        let config = ProjectConfig(bundleID: "b", keyID: "K", issuerID: "I", locales: ["en-US", "en-GB", "de-DE"],
                                   usesSourceCreative: ["de-DE", "en-GB", "en-US", "fr-FR"])
        let kinds = Validator(config: config).validateSourceCreative().map(\.kind)
        #expect(kinds == [.sourceCreativeLocaleReadsDifferently, .sourceCreativeLocaleNotUsable,
                          .sourceCreativeLocaleNotUsable])
    }

    @Test func warnsAboutAFileWithNoRole() {
        #expect(kinds(Art.folder([:], strays: ["banner.png"])) == [.creativeFileNotKnown])
    }

    @Test func refusesAFileTypeAndAnUnreadableFile() {
        #expect(headerKinds(Art.image("header.gif", 3840, 1646)) == [.creativeWrongFileType])
        let broken = CreativeFile(url: URL(fileURLWithPath: "/tmp/header.png"), fileName: "header.png", byteCount: 0,
                                  media: .image, pixelWidth: nil, pixelHeight: nil, hasAlpha: nil,
                                  duration: nil, frameRate: nil)
        #expect(headerKinds(broken) == [.creativeUnreadable])
    }

    @Test func letsTheSearchResultsShowAUniversalHeader() {
        #expect(kinds(Art.folder([.header: [Art.image("header.png", 5244, 2950)]])).isEmpty)
    }

    @Test(arguments: [Art.image("header.png", 3840, 1646), Art.video("header.mov", 3840, 1646)])
    func refusesAHeaderAloneThatDoesNotFitSearchResults(header: CreativeFile) {
        #expect(kinds(Art.folder([.header: [header]])) == [.creativeHeaderNotUniversal])
    }

    @Test func takesAnyHeaderSizeBesideASearchResultsFile() {
        #expect(headerKinds(Art.image("header.png", 3840, 1646)).isEmpty)
    }

    @Test func usesTheReferenceDataWhenItHasTheRole() {
        let refData = AssetLibraryRefData(
            imageSpecs: [.init(specId: "h", dimensions: .init(minWidth: 100, maxWidth: 100, minHeight: 50, maxHeight: 50),
                               fileExtensions: [".png"])],
            placementTypes: [.init(placementTypeId: .productPageHeader, acceptsAssetCategories: [.creativeAssets],
                                   specMappings: [.init(placementGroupId: CreativeRole.group, specs: ["h"])])]
        )
        let config = ProjectConfig(bundleID: "b", keyID: "K", issuerID: "I", locales: ["en-US"])
        let validator = Validator(config: config, refData: refData)
        let search = Art.image("search-results.png", 1920, 1280)
        #expect(validator.validateCreativeFolder(Art.folder([.header: [Art.image("header.png", 100, 50)],
                                                             .searchResults: [search]]), root: "c").isEmpty)
        #expect(validator.validateCreativeFolder(Art.folder([.header: [Art.image("header.png", 3840, 1646)],
                                                             .searchResults: [search]]), root: "c")
            .map(\.kind) == [.creativeWrongSize])
    }

    @Test func readsARatio() throws {
        let threeByTwo = try #require(CreativeRules.ratio("3:2"))
        #expect(threeByTwo.0 == 3 && threeByTwo.1 == 2)
        let wide = try #require(CreativeRules.ratio("21:9"))
        #expect(wide.0 == 21 && wide.1 == 9)
        #expect(CreativeRules.ratio("wide") == nil)
    }
}

// MARK: - The plan

struct CreativePlanTests {
    let files: LibraryFiles

    init() throws {
        files = try LibraryFiles()
    }

    func art(_ name: String) throws -> CreativeFile {
        let file = try files.file(name)
        return CreativeFile(url: file.url, fileName: name, byteCount: file.byteCount, media: .image,
                            pixelWidth: 5244, pixelHeight: 2950, hasAlpha: false, duration: nil, frameRate: nil)
    }

    static func placed(_ id: String, asset: String, type: PlacementType, locale: String = "en-US") -> RemotePlacement {
        RemotePlacement(id: id, locale: locale, type: type, group: CreativeRole.group, state: .parentPrepareForSubmission,
                        asset: RemoteLibraryAsset(id: asset, media: .image, state: .approved))
    }

    @Test func putsUpAHeaderInOneLanguageOnly() throws {
        defer { files.remove() }
        var folder = CreativeFolder()
        folder.files["en-US"] = try [.header: [art("header.png")], .searchResults: [art("search-results.png")]]

        let plans = CreativePlanner.plans(folder: folder, locales: ["de-DE", "en-US"], placements: [],
                                          record: AssetRecord())

        #expect(plans.map(\.id) == ["en-US|header", "en-US|search-results"])
        #expect(plans.first?.library.uploads == 1)
        #expect(plans.first?.file?.libraryFile.category == .creativeAssets)
    }

    @Test func placesOneAssetTwiceForAUniversalHeader() throws {
        defer { files.remove() }
        var folder = CreativeFolder()
        folder.files["en-US"] = try [.header: [art("header.png")]]

        let plans = CreativePlanner.plans(folder: folder, locales: ["en-US"], placements: [],
                                          record: AssetRecord())

        #expect(plans.map(\.role) == [.header, .searchResults])
        #expect(plans.last?.usesHeader == true)
        let targets = plans.map {
            LibraryPusher.Target(id: $0.id, label: $0.locale, deviceClassID: $0.role.rawValue,
                                 parent: .versionLocalization(id: "l"), files: $0.file.map { [$0.libraryFile] } ?? [],
                                 slot: $0.library)
        }
        #expect(LibraryPusher.uploads(in: targets).count == 1, "one upload, two placements")
    }

    /// App Store Connect shows the primary language's art on a language with
    /// none, so a language with no files takes off what was placed there.
    @Test func leavesALanguageWithNoArtToThePrimaryLanguage() throws {
        defer { files.remove() }
        var folder = CreativeFolder()
        folder.files["en-US"] = try [.header: [art("header.png")]]

        let plans = CreativePlanner.plans(
            folder: folder, locales: ["en-GB", "en-US"],
            placements: [Self.placed("p1", asset: "a1", type: .productPageHeader, locale: "en-GB")],
            record: AssetRecord()
        )

        #expect(plans.map(\.id) == ["en-GB|header", "en-US|header", "en-US|search-results"])
        #expect(plans.first?.file == nil)
        #expect(plans.first?.action == .replace(removing: 1, adding: 0))
    }

    @Test func takesOffAPlacementWhoseFileIsGone() {
        let plans = CreativePlanner.plans(
            folder: CreativeFolder(), locales: ["en-US"],
            placements: [Self.placed("p1", asset: "a1", type: .productPageHeader)],
            record: AssetRecord()
        )
        #expect(plans.first?.action == .replace(removing: 1, adding: 0))
    }

    @Test func leavesAHeaderTheLibraryAlreadyShows() throws {
        defer { files.remove() }
        let header = try art("header.png")
        var folder = CreativeFolder()
        folder.files["en-US"] = [.header: [header]]
        var record = AssetRecord()
        try record.record(md5: FileChecksum.md5(of: header.url), .init(
            assetID: "a1", media: .image, fileName: "header.png", fileSize: header.byteCount, state: .approved
        ))

        let plans = CreativePlanner.plans(folder: folder, locales: ["en-US"],
                                          placements: [Self.placed("p1", asset: "a1", type: .productPageHeader),
                                                       Self.placed("p2", asset: "a1", type: .searchResults)],
                                          record: record)
        #expect(plans.allSatisfy { $0.changesAnything == false })
    }

    @Test func readsTheFolderOfAVersionAndATreatment() throws {
        defer { files.remove() }
        let fixture = try FixtureProject()
        defer { fixture.remove() }
        try fixture.writeConfig(ProjectConfig(bundleID: "b", keyID: "K", issuerID: "I", locales: ["en-US"]))
        let project = try fixture.load()
        let version = project.creativeURL(version: "1.0").appending(path: "en-US")
        let treatment = project.experimentsURL.appending(path: "Fall/Treatment A/creative/en-US")
        for folder in [version, treatment] {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data("x".utf8).write(to: folder.appending(path: "header.png"))
            try Data("x".utf8).write(to: folder.appending(path: "notes.txt"))
        }

        let content = try ContentStore.load(version: "1.0", in: project)
        #expect(content.creativeFolder.file(locale: "en-US", role: .header)?.fileName == "header.png")
        #expect(content.creativeFolder.strays["en-US"] == ["notes.txt"])

        let experiments = ExperimentContentStore.load(in: project)
        #expect(experiments.creative["Fall/Treatment A"]?.file(locale: "en-US", role: .header) != nil)
        #expect(experiments.screenshots.keys.contains { $0.locale == "creative" } == false)
    }

    @Test func plansTheArtOfATreatment() throws {
        defer { files.remove() }
        var folder = CreativeFolder()
        folder.files["en-US"] = try [.header: [art("header.png")]]
        let plan = ExperimentPlanner.plan(
            local: ExperimentContent(creative: ["Fall/Treatment A": folder]),
            config: ProjectConfig(bundleID: "b", keyID: "K", issuerID: "I", locales: ["en-US"]),
            remote: LibraryExperimentPlanTests.remote(placements: []), record: AssetRecord()
        )
        #expect(plan.creativeSets.map(\.plan.role) == [.header, .searchResults])
        #expect(PushSession.targets(in: plan).map(\.parent) == [.treatmentLocalization(id: "tl-en"),
                                                                .treatmentLocalization(id: "tl-en")])
    }
}

// MARK: - What a terminal shows

struct LibraryReportLineTests {
    @Test func listsWhatChangesInATreatment() throws {
        let files = try LibraryFiles()
        defer { files.remove() }
        let header = try CreativePlanTests().art("header.png")
        var art = CreativeFolder()
        art.files["en-US"] = [.header: [header]]
        let shot = try files.file("01.mov")
        let plan = ExperimentPlanner.plan(
            local: ExperimentContent(
                previews: [ExperimentSlot(experiment: "Fall", treatment: "Treatment A", locale: "en-US",
                                          deviceClassID: "iphone-6.9"): [PreviewFile(url: shot.url, fileName: "01.mov",
                                                                                     byteCount: shot.byteCount)]],
                creative: ["Fall/Treatment A": art]
            ),
            config: ProjectConfig(bundleID: "b", keyID: "K", issuerID: "I", locales: ["en-US"]),
            remote: LibraryExperimentPlanTests.remote(placements: []), record: AssetRecord()
        )

        #expect(plan.libraryLines(treatmentID: "t1") == [
            "en-US/iphone-6.9 previews: remove 0, add 1",
            "en-US header: put up header.png",
            "en-US search-results: show the header"
        ])
        #expect(plan.libraryLines(treatmentID: "another").isEmpty)
    }

    @Test(arguments: [(true, "change the poster frame"), (false, "change the order")])
    func saysWhenOnlyTheOrderOrThePosterFrameChanges(poster: Bool, words: String) {
        let current = [CreativePlanTests.placed("p2", asset: "b", type: .appPreview),
                       CreativePlanTests.placed("p1", asset: "a", type: .appPreview)]
        let slot = LibrarySlot(group: "G", type: .appPreview, wanted: poster ? ["b", "a"] : ["a", "b"],
                               checksums: [nil, nil], current: current,
                               posterFrames: poster ? ["a": "00:00:01:00"] : [:])
        #expect(ExperimentPlan.describe(slot) == words)
    }

    @Test func countsEachFileOnceAndEachSlotsWorkInTheProgress() {
        let current = [CreativePlanTests.placed("p1", asset: "old", type: .appScreenshot)]
        let one = LibrarySlot(group: "G", type: .appScreenshot, wanted: [nil, nil], checksums: ["x", "y"], current: current)
        let two = LibrarySlot(group: "H", type: .appScreenshot, wanted: [nil], checksums: ["x"], current: [])
        let plan = ChangePlan(
            versionString: "1.0", versionState: .prepareForSubmission, textChanges: [], missingLocales: [],
            screenshotPlans: [
                .init(locale: "en-US", deviceClass: .iPhone69, localFiles: [], library: one),
                .init(locale: "de-DE", deviceClass: .iPhone69, localFiles: [], library: two)
            ],
            blocked: [], skipped: []
        )
        // Two files up, one slot takes a placement off, each slot makes its
        // placements, and one slot sets an order.
        #expect(PushProgress.steps(for: .screenshots, in: plan) == 6)
    }
}

// MARK: - The specs App Store Connect sent

/// The header and search results specs of the reference data App Store
/// Connect sent for a real app, on 2026-10-07.
struct CreativeRealSpecTests {
    static let refData: AssetLibraryRefData = {
        func image(_ id: String, _ dims: AssetLibraryRefData.Dimensions, _ ratio: String, _ exts: [String],
                   universal: Bool) -> AssetLibraryRefData.ImageSpec {
            var spec = AssetLibraryRefData.ImageSpec(
                specId: id, dimensions: dims,
                alphaAllowed: false, fileExtensions: exts, universalAsset: universal
            )
            spec.aspectRatio = ratio
            return spec
        }
        return AssetLibraryRefData(
            imageSpecs: [
                image("wide", .init(minWidth: 5244, maxWidth: 5244, minHeight: 2950, maxHeight: 2950), "16:9",
                      [".png"], universal: true),
                image("header", .init(minWidth: 3840, maxWidth: 3840, minHeight: 1646, maxHeight: 1646), "21:9",
                      [".png"], universal: false),
                image("search", .init(minWidth: 1920, maxWidth: 3840, minHeight: 1280, maxHeight: 2560), "3:2",
                      [".jpg", ".jpeg", ".png"], universal: false)
            ],
            placementTypes: [
                .init(placementTypeId: .productPageHeader, acceptsAssetCategories: [.creativeAssets],
                      specMappings: [.init(placementGroupId: CreativeRole.group, specs: ["wide", "header"])]),
                .init(placementTypeId: .searchResults, acceptsAssetCategories: [.creativeAssets],
                      specMappings: [.init(placementGroupId: CreativeRole.group, specs: ["search", "wide"])])
            ]
        )
    }()

    func problems(_ folder: CreativeFolder) -> [Problem] {
        let config = ProjectConfig(bundleID: "b", keyID: "K", issuerID: "I", locales: ["en-US"])
        return Validator(config: config, refData: Self.refData).validateCreativeFolder(folder, root: "c")
    }

    @Test func takesTheHeaderAndSearchResultsSizesItNames() {
        let folder = Art.folder([.header: [Art.image("header.png", 3840, 1646)],
                                 .searchResults: [Art.image("search-results.png", 3840, 2560)]])
        #expect(problems(folder).isEmpty)
    }

    @Test func takesTheWideAssetForBothRoles() {
        #expect(problems(Art.folder([.header: [Art.image("header.png", 5244, 2950)]])).isEmpty)
    }

    @Test func refusesTheHeaderAsAJpegWhereItNamesOnlyPng() {
        let folder = Art.folder([.header: [Art.image("header.jpg", 3840, 1646)],
                                 .searchResults: [Art.image("search-results.png", 3840, 2560)]])
        #expect(problems(folder).map(\.kind) == [.creativeWrongSize])
    }

    @Test func stillRefusesASearchResultsImageOffItsRatio() {
        #expect(problems(Art.folder([.searchResults: [Art.image("search-results.png", 2400, 1700)]])).map(\.kind)
            == [.creativeWrongSize])
    }

    @Test func writesTheSizeWithNoGroupingWhateverTheNumberFormat() {
        let problem = problems(Art.folder([.header: [Art.image("header.png", 3841, 1646)]])).first
        #expect(problem?.message.english == "header.png is 3841x1646 pixels.")
    }
}

struct CreativeSummaryTests {
    @Test func countsTheArtInTheSummary() throws {
        let files = try LibraryFiles()
        defer { files.remove() }
        var folder = CreativeFolder()
        folder.files["en-US"] = try [.header: [CreativePlanTests().art("header.png")]]
        let creative = CreativePlanner.plans(folder: folder, locales: ["en-US"], placements: [],
                                             record: AssetRecord())
        let plan = ChangePlan(versionString: "2.1", versionState: .prepareForSubmission, textChanges: [],
                              missingLocales: [], screenshotPlans: [], creativePlans: creative,
                              blocked: [], skipped: [])

        #expect(ChangePlanFormatter.summary(plan).contains("2 header and search results assets"))
    }

    @Test func takesTheArtOffALanguageWithNone() throws {
        let files = try LibraryFiles()
        defer { files.remove() }
        var folder = CreativeFolder()
        folder.files["en-US"] = try [.header: [CreativePlanTests().art("header.png")]]
        let creative = CreativePlanner.plans(
            folder: folder, locales: ["en-GB", "en-US"],
            placements: [CreativePlanTests.placed("p1", asset: "a1", type: .productPageHeader, locale: "en-GB")],
            record: AssetRecord()
        )
        let plan = ChangePlan(versionString: "2.1", versionState: .prepareForSubmission, textChanges: [],
                              missingLocales: [], screenshotPlans: [], creativePlans: creative,
                              blocked: [], skipped: [])

        #expect(ChangePlanFormatter.lines(for: plan) == [
            "Header and search results:",
            "  en-GB, header: will be removed",
            "  en-US, header: put up header.png",
            "  en-US, search results: show the header, header.png",
            ""
        ])
    }
}
