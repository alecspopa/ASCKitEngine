import ASCKitAPI
import Foundation
import Testing
@testable import ASCKitProject

/// One path for the screenshots of a version, a treatment and a custom product
/// page: where they go, how a push treats an empty set, and which place takes
/// no change.
final class ScreenshotPlaceTests {
    let fixture: FixtureProject
    let project: Project
    let deviceClass = DeviceClass.iPhone69

    static let places: [LibraryContentPlace] = [
        .version("1.0"),
        .treatment(experiment: "Bigger buttons", treatment: "Treatment A"),
        .customPage("Summer")
    ]

    init() throws {
        fixture = try FixtureProject()
        let config = ProjectConfig(
            bundleID: "com.example.Demo",
            keyID: "ABC123",
            issuerID: "issuer",
            sourceLocale: "en-US",
            locales: ["en-US"],
            deviceClasses: [DeviceClass.iPhone69.id, DeviceClass.iMessageIPhone69.id, DeviceClass.watchUltra.id]
        )
        let url = try fixture.writeConfig(config)
        project = Project(configURL: url, config: config)
    }

    deinit {
        fixture.remove()
    }

    private func incoming(_ name: String) throws -> URL {
        let folder = fixture.rootURL.appending(path: "incoming")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: name)
        try PNGWriter.write(to: url, width: 1320, height: 2868, hasAlpha: false, seed: name)
        return url
    }

    // MARK: - Writing

    @Test(arguments: places)
    func addsReordersAndRemovesInEveryPlace(place: LibraryContentPlace) throws {
        try ContentWriter.addScreenshots(
            from: [incoming("hero.png"), incoming("shop.png")], locale: "en-US", deviceClass: deviceClass,
            at: place, in: project
        )
        let folder = project.screenshotsURL(place, locale: "en-US", deviceClassID: deviceClass.id)
        #expect(project.screenshotFolder(place).screenshots[ScreenshotSlot(locale: "en-US", deviceClassID: deviceClass.id)]?
            .map(\.fileName) == ["01-hero-iPhone-6.9-en_US.png", "02-shop-iPhone-6.9-en_US.png"])

        let moved = try ContentWriter.reorderScreenshots(
            order: ["02-shop-iPhone-6.9-en_US.png", "01-hero-iPhone-6.9-en_US.png"],
            locale: "en-US", deviceClass: deviceClass, at: place, in: project
        )
        #expect(moved.map(\.fileName) == ["01-shop-iPhone-6.9-en_US.png", "02-hero-iPhone-6.9-en_US.png"])

        let left = try ContentWriter.removeScreenshots(
            named: ["01-shop-iPhone-6.9-en_US.png"], locale: "en-US", deviceClass: deviceClass, at: place, in: project
        )
        #expect(left.map(\.fileName) == ["01-hero-iPhone-6.9-en_US.png"])
        #expect(FileManager.default.fileExists(atPath: folder.appending(path: ScreenshotFolder.emptiedMarkerName).path) == false)
    }

    @Test(arguments: places)
    func marksASetThatWasEmptiedOnPurpose(place: LibraryContentPlace) throws {
        try ContentWriter.addScreenshots(
            from: [incoming("hero.png")], locale: "en-US", deviceClass: deviceClass, at: place, in: project
        )

        let trashed = try ContentWriter.removeAllScreenshots(
            locale: "en-US", deviceClass: deviceClass, at: place, in: project
        )

        #expect(trashed.count == 1)
        #expect(project.screenshotFolder(place).emptied == [ScreenshotSlot(locale: "en-US", deviceClassID: deviceClass.id)])

        try ContentWriter.keepRemoteScreenshots(locale: "en-US", deviceClass: deviceClass, at: place, in: project)
        #expect(project.screenshotFolder(place).emptied.isEmpty)
    }

    /// A treatment holds its previews and art beside the language folders, and
    /// none of them reads as a language.
    @Test func readsNoLanguageFromTheFoldersBesideTheLanguages() throws {
        let place = LibraryContentPlace.treatment(experiment: "Bigger buttons", treatment: "Treatment A")
        try ContentWriter.addScreenshots(
            from: [incoming("hero.png")], locale: "en-US", deviceClass: deviceClass, at: place, in: project
        )
        let previews = project.previewsURL(place, locale: "en-US", deviceClassID: deviceClass.id)
        try FileManager.default.createDirectory(at: previews, withIntermediateDirectories: true)

        #expect(project.screenshotFolder(place).locales == ["en-US"])
    }

    @Test func putsTheNamesOfATreatmentRight() throws {
        let place = LibraryContentPlace.treatment(experiment: "Bigger buttons", treatment: "Treatment A")
        let folder = project.screenshotsURL(place, locale: "en-US", deviceClassID: deviceClass.id)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try PNGWriter.write(to: folder.appending(path: "01-hero.png"), width: 1320, height: 2868, hasAlpha: false, seed: "h")

        let moved = try ContentWriter.repairNames(at: place, in: project)

        #expect(moved.map(\.to) == ["01-hero-iPhone-6.9-en_US.png"])
    }

    // MARK: - The push

    private let placement = RemotePlacement(
        id: "p1", locale: "en-US", type: .appScreenshot, group: DeviceClass.iPhone69.placementGroup,
        state: .parentPrepareForSubmission,
        asset: RemoteLibraryAsset(id: "a1", media: .image, fileName: "01-a.png", state: .approved)
    )

    @Test func leavesAnEmptySetAloneUnlessItWasEmptiedOnPurpose() {
        let alone = LibraryPlanner.screenshotSet(
            files: [], placements: [placement], locale: "en-US", deviceClass: deviceClass,
            emptied: false, record: AssetRecord()
        )
        let emptied = LibraryPlanner.screenshotSet(
            files: [], placements: [placement], locale: "en-US", deviceClass: deviceClass,
            emptied: true, record: AssetRecord()
        )

        #expect(alone == nil)
        #expect(emptied.map(LibraryPlanner.action(for:)) == .replace(removing: 1, adding: 0))
    }

    @Test func plansNothingForASetThatIsEmptyOnBothSides() {
        #expect(LibraryPlanner.screenshotSet(
            files: [], placements: [], locale: "en-US", deviceClass: deviceClass, emptied: true, record: AssetRecord()
        ) == nil)
    }

    // MARK: - Device classes

    @Test func takesOneRuleForTheDeviceClassesOfEachPlace() {
        let config = project.config
        let ids = { (place: LibraryContentPlace, platform: Platform?) in
            config.screenshotDeviceClasses(for: place, platform: platform).map(\.id)
        }

        #expect(ids(.version("1.0"), nil).count == 3)
        #expect(ids(.customPage("Summer"), nil) == [DeviceClass.iPhone69.id])
        #expect(ids(.treatment(experiment: "t", treatment: "a"), .ios).count == 3)
        #expect(ids(.treatment(experiment: "t", treatment: "a"), .macOS).isEmpty)
        #expect(ids(.treatment(experiment: "t", treatment: "a"), nil).count == 3)
    }

    // MARK: - The lock

    @Test func locksATestInReviewAndNoOther() {
        let remote = RemoteExperiments(appID: "app1", experiments: [
            RemoteExperiment(id: "e1", name: "Draft", state: .prepareForSubmission, platform: .ios, treatments: []),
            RemoteExperiment(id: "e2", name: "Running", state: .approved, platform: .ios, treatments: [])
        ])
        let snapshot = ExperimentSnapshot(remote)
        let lock = { (test: String) in
            ScreenshotPlaceLock.lock(
                for: .treatment(experiment: test, treatment: "A"), listing: nil, experiments: snapshot, pages: nil
            )
        }

        #expect(lock("Draft") == nil)
        #expect(lock("Running") == .test(folder: "Running", state: "APPROVED"))
        #expect(lock("Unknown") == nil)
        #expect(ScreenshotPlaceLock.lock(for: .version("1.0"), listing: nil, experiments: nil, pages: nil) == nil)
    }
}
