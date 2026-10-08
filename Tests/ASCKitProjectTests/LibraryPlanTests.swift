import ASCKitAPI
import Foundation
import Testing
@testable import ASCKitProject

/// Real files with chosen bytes, because a slot is decided by their MD5.
struct LibraryFiles {
    let folder: URL

    init() throws {
        folder = FixtureProject.fixturesRoot.appending(path: "library-files-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    func remove() {
        try? FileManager.default.removeItem(at: folder)
    }

    /// A file whose bytes are its contents string, so two files with the same
    /// string have the same MD5.
    func file(_ name: String, contents: String? = nil) throws -> ScreenshotFile {
        let data = Data((contents ?? name).utf8)
        let url = folder.appending(path: name)
        try data.write(to: url)
        return ScreenshotFile(url: url, fileName: name, byteCount: data.count,
                              pixelWidth: 1290, pixelHeight: 2796, hasAlpha: false)
    }

    static func md5(_ file: ScreenshotFile) throws -> String {
        try FileChecksum.md5(of: file.url)
    }

    /// A record that names each file's bytes with the asset id given.
    static func record(_ pairs: [(ScreenshotFile, String)], state: LibraryAssetState? = .approved) throws -> AssetRecord {
        var record = AssetRecord()
        for (file, id) in pairs {
            try record.record(md5: md5(file), AssetRecord.Entry(
                assetID: id, media: .image, fileName: file.fileName, fileSize: file.byteCount, state: state
            ))
        }
        return record
    }
}

enum Placed {
    static let group = DeviceClass.iPhone69.placementGroup

    static func placement(
        _ id: String,
        asset: String,
        locale: String = "en-US",
        state: LibraryAssetState = .approved,
        group: String = group
    ) -> RemotePlacement {
        RemotePlacement(
            id: id, locale: locale, type: .appScreenshot, group: group, state: .parentPrepareForSubmission,
            asset: RemoteLibraryAsset(id: asset, media: .image, fileName: "\(asset).png", state: state)
        )
    }
}

struct LibrarySlotTests {
    let files: LibraryFiles

    init() throws {
        files = try LibraryFiles()
    }

    func slot(_ local: [ScreenshotFile], current: [RemotePlacement], record: AssetRecord) -> LibrarySlot {
        LibraryPlanner.slot(files: local.map(\.libraryFile), current: current, record: record, group: Placed.group, type: .appScreenshot)
    }

    @Test func leavesASlotThatHoldsTheseFilesInThisOrder() throws {
        defer { files.remove() }
        let one = try files.file("01.png"), two = try files.file("02.png")
        let slot = try slot([one, two],
                            current: [Placed.placement("p1", asset: "a1"), Placed.placement("p2", asset: "a2")],
                            record: LibraryFiles.record([(one, "a1"), (two, "a2")]))

        #expect(slot.isUnchanged)
        #expect(LibraryPlanner.action(for: slot) == .unchanged)
    }

    @Test func uploadsANewFileAndKeepsTheRest() throws {
        defer { files.remove() }
        let one = try files.file("01.png"), two = try files.file("02.png")
        let slot = try slot([one, two], current: [Placed.placement("p1", asset: "a1")],
                            record: LibraryFiles.record([(one, "a1")]))

        #expect(slot.wanted == ["a1", nil])
        #expect(slot.uploads == 1)
        #expect(slot.kept.map(\.id) == ["p1"])
        #expect(LibraryPlanner.action(for: slot) == .replace(removing: 0, adding: 1))
    }

    @Test func removesThePlacementOfARemovedFile() throws {
        defer { files.remove() }
        let one = try files.file("01.png")
        let slot = try slot([one], current: [Placed.placement("p1", asset: "a1"), Placed.placement("p2", asset: "a2")],
                            record: LibraryFiles.record([(one, "a1")]))

        #expect(slot.toRemove.map(\.id) == ["p2"])
        #expect(LibraryPlanner.action(for: slot) == .replace(removing: 1, adding: 0))
    }

    @Test func onlyReordersWhenTheOrderAloneChanged() throws {
        defer { files.remove() }
        let one = try files.file("01.png"), two = try files.file("02.png")
        let slot = try slot([one, two],
                            current: [Placed.placement("p2", asset: "a2"), Placed.placement("p1", asset: "a1")],
                            record: LibraryFiles.record([(one, "a1"), (two, "a2")]))

        #expect(slot.isUnchanged == false)
        #expect(slot.uploads == 0)
        #expect(slot.toRemove.isEmpty)
        #expect(LibraryPlanner.action(for: slot) == .replace(removing: 0, adding: 0))
    }

    @Test func replacesAFileThatChangedInItsPlace() throws {
        defer { files.remove() }
        let old = try files.file("01.png", contents: "old")
        let record = try LibraryFiles.record([(old, "a1")])
        let new = try files.file("01.png", contents: "new")
        let slot = slot([new], current: [Placed.placement("p1", asset: "a1")], record: record)

        #expect(slot.wanted == [nil])
        #expect(LibraryPlanner.action(for: slot) == .replace(removing: 1, adding: 1))
    }

    @Test func removesEverythingWhenTheFolderIsEmpty() {
        let slot = slot([], current: [Placed.placement("p1", asset: "a1")], record: AssetRecord())
        #expect(LibraryPlanner.action(for: slot) == .replace(removing: 1, adding: 0))
    }

    @Test func uploadsEverythingIntoAnEmptySlot() throws {
        defer { files.remove() }
        let slot = try slot([files.file("01.png"), files.file("02.png")], current: [], record: AssetRecord())
        #expect(LibraryPlanner.action(for: slot) == .replace(removing: 0, adding: 2))
    }

    @Test func leavesAnEmptySlotWithNoFilesAlone() {
        #expect(slot([], current: [], record: AssetRecord()).isUnchanged)
    }

    @Test func replacesAnAssetTheRecordDoesNotKnow() throws {
        defer { files.remove() }
        let one = try files.file("01.png")
        let slot = slot([one], current: [Placed.placement("p1", asset: "from-the-website")], record: AssetRecord())

        #expect(slot.toRemove.map(\.id) == ["p1"])
        #expect(slot.uploads == 1)
    }

    @Test(arguments: [LibraryAssetState.failed, .archived])
    func uploadsAgainAnAssetThatCannotBePlaced(state: LibraryAssetState) throws {
        defer { files.remove() }
        let one = try files.file("01.png")
        let slot = try slot([one], current: [Placed.placement("p1", asset: "a1", state: state)],
                            record: LibraryFiles.record([(one, "a1")]))

        #expect(slot.wanted == [nil])
        #expect(slot.toRemove.map(\.id) == ["p1"])
    }

    @Test func usesTheRecordsStateForAnAssetNotPlacedHere() throws {
        defer { files.remove() }
        let one = try files.file("01.png")
        let slot = try slot([one], current: [], record: LibraryFiles.record([(one, "a1")], state: .failed))
        #expect(slot.wanted == [nil])
    }

    @Test func waitsForAnAssetStillProcessing() throws {
        defer { files.remove() }
        let one = try files.file("01.png")
        let slot = try slot([one], current: [Placed.placement("p1", asset: "a1", state: .uploadComplete)],
                            record: LibraryFiles.record([(one, "a1")]))

        #expect(slot.wanted == ["a1"], "the asset is there, it is only not finished")
        #expect(LibraryPlanner.stillArriving(slot).map(\.id) == ["p1"])
    }

    @Test func keepsOnePlacementForEachTimeTheSameBytesAreWanted() throws {
        defer { files.remove() }
        let one = try files.file("01.png", contents: "same")
        let two = try files.file("02.png", contents: "same")
        let slot = try slot([one, two],
                            current: [Placed.placement("p1", asset: "a1"), Placed.placement("p2", asset: "a1"),
                                      Placed.placement("p3", asset: "a1")],
                            record: LibraryFiles.record([(one, "a1")]))

        #expect(slot.wanted == ["a1", "a1"])
        #expect(slot.kept.map(\.id) == ["p1", "p2"])
        #expect(slot.toRemove.map(\.id) == ["p3"])
    }

    @Test func picksOnlyTheSlotsOwnPlacements() {
        let placements = [
            Placed.placement("en", asset: "a"),
            Placed.placement("de", asset: "a", locale: "de-DE"),
            Placed.placement("ipad", asset: "a", group: DeviceClass.iPad13.placementGroup)
        ]
        let current = LibraryPlanner.current(in: placements, locale: "en-US", group: Placed.group, type: .appScreenshot)
        #expect(current.map(\.id) == ["en"])
        #expect(LibraryPlanner.current(in: placements, locale: "en-US", group: Placed.group, type: .appPreview).isEmpty)
    }
}

// MARK: - The plan of a version

struct LibraryVersionPlanTests {
    let fixture: FixtureProject

    init() throws {
        fixture = try FixtureProject()
    }

    func listing(state: AppVersionState = .prepareForSubmission, placements: [RemotePlacement]) -> RemoteListing {
        RemoteListing(
            appID: "app1", appName: "Demo", bundleID: "com.example.MyApp",
            appInfoID: "info1", appInfoState: .prepareForSubmission,
            versionID: "v1", versionString: "1.0", versionState: state,
            appInfoLocalizations: [:],
            versionLocalizations: [
                "en-US": RemoteLocalization(id: "l-en", locale: "en-US", values: [:]),
                "de-DE": RemoteLocalization(id: "l-de", locale: "de-DE", values: [:]),
                "fr-FR": RemoteLocalization(id: "l-fr", locale: "fr-FR", values: [:])
            ],
            screenshotSets: [],
            placements: placements
        )
    }

    /// The same image, byte for byte, in three languages.
    func content() throws -> VersionContent {
        let locales = ["en-US", "de-DE", "fr-FR"]
        try fixture.writeConfig(ProjectConfig(
            bundleID: "com.example.MyApp", keyID: "ABC123", issuerID: "issuer",
            locales: locales, deviceClasses: [DeviceClass.iPhone69.id]
        ))
        for locale in locales {
            try fixture.writeCopy(AppInformation(locale: locale, status: .approved, fields: AppInformation.Fields(
                name: "Stocked", subtitle: "Pantry", keywords: "pantry", description: "Words.",
                whatsNew: "New.", supportUrl: "https://example.com/support",
                privacyPolicyUrl: "https://example.com/privacy"
            )))
            // The same seed makes the same bytes in every language.
            try fixture.writeScreenshot(locale: locale, deviceClassID: DeviceClass.iPhone69.id,
                                        named: "01-a.png", width: 1320, height: 2868, seed: "same")
        }
        return try ContentStore.load(version: "1.0", in: fixture.load())
    }

    @Test func plansAgainstTheLibraryWhenGivenARecord() throws {
        defer { fixture.remove() }
        let local = try content()
        let plan = try Planner.plan(local: local, config: fixture.load().config,
                                    remote: listing(placements: []), record: AssetRecord())

        #expect(plan.screenshotPlans.count == 3)
        #expect(plan.screenshotPlans.allSatisfy { $0.library != nil })
    }

    @Test func uploadsOneImageThatThreeLanguagesUseOnce() throws {
        defer { fixture.remove() }
        let listing = listing(placements: [])
        let plan = try Planner.plan(local: content(), config: fixture.load().config, remote: listing, record: AssetRecord())

        let targets = PushSession.targets(in: plan, listing: listing)
        #expect(targets.count == 3)
        #expect(LibraryPusher.uploads(in: targets).count == 1)
        #expect(Set(targets.map(\.parent)) == [
            .versionLocalization(id: "l-en"), .versionLocalization(id: "l-de"), .versionLocalization(id: "l-fr")
        ])
    }

    @Test func blocksTheSlotsOfAVersionThatTakesNoImages() throws {
        defer { fixture.remove() }
        let plan = try Planner.plan(local: content(), config: fixture.load().config,
                                    remote: listing(state: .readyForDistribution, placements: []), record: AssetRecord())
        #expect(plan.blocked(.screenshots).isEmpty == false)
    }

    @Test func losesNothingWhenASlotChanges() throws {
        defer { fixture.remove() }
        let listing = listing(placements: [Placed.placement("p1", asset: "only-on-the-website")])
        let plan = try Planner.plan(local: content(), config: fixture.load().config, remote: listing, record: AssetRecord())

        #expect(plan.hasScreenshotChanges)
    }
}

// MARK: - The plan of a draft test

struct LibraryExperimentPlanTests {
    let files: LibraryFiles

    init() throws {
        files = try LibraryFiles()
    }

    static let config = ProjectConfig(
        bundleID: "com.example.MyApp", keyID: "K", issuerID: "I",
        locales: ["en-US"], deviceClasses: [DeviceClass.iPhone69.id]
    )

    static func remote(placements: [RemotePlacement]) -> RemoteExperiments {
        RemoteExperiments(appID: "app1", experiments: [
            RemoteExperiment(id: "e1", name: "Fall", state: .prepareForSubmission, platform: .ios, treatments: [
                RemoteTreatment(id: "t1", name: "Treatment A", localizations: [
                    RemoteTreatmentLocalization(id: "tl-en", locale: "en-US", placements: placements)
                ])
            ])
        ])
    }

    func local(_ files: [ScreenshotFile]) -> ExperimentContent {
        ExperimentContent(screenshots: [
            ExperimentSlot(experiment: "Fall", treatment: "Treatment A", locale: "en-US",
                           deviceClassID: DeviceClass.iPhone69.id): files
        ])
    }

    @Test func plansATreatmentAgainstItsPlacements() throws {
        defer { files.remove() }
        let one = try files.file("01.png")
        let plan = try ExperimentPlanner.plan(
            local: local([one]), config: Self.config,
            remote: Self.remote(placements: [Placed.placement("p1", asset: "a1")]),
            record: LibraryFiles.record([(one, "a1")])
        )

        let set = try #require(plan.sets.first)
        #expect(set.library.isUnchanged)
        #expect(set.remoteCount == 1)
        #expect(plan.hasChanges == false)
    }

    @Test func pushesATreatmentOntoItsOwnLanguage() throws {
        defer { files.remove() }
        let plan = try ExperimentPlanner.plan(
            local: local([files.file("01.png")]), config: Self.config,
            remote: Self.remote(placements: []), record: AssetRecord()
        )

        let targets = PushSession.targets(in: plan)
        #expect(targets.map(\.parent) == [.treatmentLocalization(id: "tl-en")])
        #expect(targets.first?.label == "Fall / Treatment A / en-US")
        #expect(plan.imagesToAdd == 1)
    }
}

// MARK: - Plans made by hand

extension ChangePlan.ScreenshotPlan {
    /// A slot that takes `removing` placements off and puts up `uploading`
    /// new files, each with bytes of its own.
    static func stub(
        _ locale: String = "en-US",
        deviceClass: DeviceClass = .iPhone69,
        removing: Int,
        uploading: Int
    ) -> ChangePlan.ScreenshotPlan {
        let current = (0 ..< removing).map { Placed.placement("p\($0)", asset: "old\($0)", locale: locale) }
        return ChangePlan.ScreenshotPlan(
            locale: locale,
            deviceClass: deviceClass,
            localFiles: [],
            library: LibrarySlot(
                group: deviceClass.placementGroup,
                type: .appScreenshot,
                wanted: Array(repeating: nil, count: uploading),
                checksums: (0 ..< uploading).map { "new\($0)" },
                current: current
            )
        )
    }
}
