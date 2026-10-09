import ASCKitAPI
import ASCKitTestSupport
import Foundation
import Testing
@testable import ASCKitProject

// MARK: - Poster frames

struct PosterFramesTests {
    @Test(arguments: [
        ("00:00:00:00", 0.0), ("00:00:05:00", 5.0), ("00:00:05:15", 5.5), ("00:01:02:00", 62.0), ("01:00:00:00", 3600.0)
    ])
    func readsATimeCode(timeCode: String, seconds: Double) {
        #expect(PosterFrames.seconds(of: timeCode) == seconds)
    }

    @Test(arguments: ["5", "00:05", "00:00:05", "00:00:60:00", "00:60:00:00", "00:00:05:30", "aa:bb:cc:dd", "", "-1:00:00:00"])
    func refusesATimeCodeWrittenAnotherWay(timeCode: String) {
        #expect(PosterFrames.seconds(of: timeCode) == nil)
    }

    @Test(arguments: [
        (0.0, "00:00:00:00"), (5.0, "00:00:05:00"), (5.5, "00:00:05:15"), (62.0, "00:01:02:00"),
        (3600.0, "01:00:00:00"), (5.51, "00:00:05:15"), (-1.0, "00:00:00:00")
    ])
    func writesATimeCode(seconds: Double, timeCode: String) {
        #expect(PosterFrames.timeCode(atSeconds: seconds) == timeCode)
    }

    /// What the poster frame sheet writes, the check reads back as the same
    /// time, at each frame rate the store takes.
    @Test(arguments: [24.0, 25.0, 30.0, 60.0])
    func readsBackTheTimeCodeItWrote(frameRate: Double) throws {
        let seconds = 12 + 7 / frameRate
        let timeCode = PosterFrames.timeCode(atSeconds: seconds, frameRate: frameRate)
        let read = try #require(PosterFrames.seconds(of: timeCode, frameRate: frameRate))
        #expect(abs(read - seconds) < 0.001)
    }

    @Test func writesReadsAndRemovesTheFile() throws {
        let folder = FixtureProject.fixturesRoot.appending(path: "poster-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        #expect(PosterFrames.load(in: folder) == [:])
        try PosterFrames.save(["01-a.mov": "00:00:03:00"], in: folder)
        #expect(PosterFrames.load(in: folder) == ["01-a.mov": "00:00:03:00"])
        try PosterFrames.save([:], in: folder)
        #expect(FileManager.default.fileExists(atPath: folder.appending(path: PosterFrames.fileName).path) == false)
    }

    @Test func readsNothingFromADamagedFile() throws {
        let folder = FixtureProject.fixturesRoot.appending(path: "poster-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data(#"["not a map"]"#.utf8).write(to: folder.appending(path: PosterFrames.fileName))

        #expect(PosterFrames.load(in: folder) == nil)
    }
}

// MARK: - Reading previews from a project

@Suite(.serialized)
struct PreviewContentTests {
    let fixture: FixtureProject

    init() throws {
        fixture = try FixtureProject()
        try fixture.writeConfig(ProjectConfig(bundleID: "b", keyID: "K", issuerID: "I", locales: ["en-US"]))
    }

    func place(_ movie: URL, in folder: URL, as name: String) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: movie, to: folder.appending(path: name))
    }

    @Test func readsTheVideosOfAVersionWithTheirPosterFrames() async throws {
        defer { fixture.remove() }
        let project = try fixture.load()
        let folder = project.previewsURL(version: "1.0", locale: "en-US", deviceClassID: "iphone-6.9")
        try await place(Movies.shared.movie("h264.mov"), in: folder, as: "02-b.mov")
        try await place(Movies.shared.movie("h264.mov"), in: folder, as: "01-a.mov")
        try PosterFrames.save(["01-a.mov": "00:00:02:00"], in: folder)

        let content = try ContentStore.load(version: "1.0", in: project)
        let previews = content.previews(locale: "en-US", deviceClassID: "iphone-6.9")

        #expect(previews.map(\.fileName) == ["01-a.mov", "02-b.mov"])
        #expect(previews.map(\.posterFrame) == ["00:00:02:00", nil])
        #expect(previews.first?.pixelWidth == 64)
    }

    @Test func notesAPosterFrameFileItCannotRead() throws {
        defer { fixture.remove() }
        let project = try fixture.load()
        let folder = project.previewsURL(version: "1.0", locale: "en-US", deviceClassID: "iphone-6.9")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("nope".utf8).write(to: folder.appending(path: PosterFrames.fileName))

        let content = try ContentStore.load(version: "1.0", in: project)
        #expect(content.previewFolder.unreadablePosterFrames == [ScreenshotSlot(locale: "en-US", deviceClassID: "iphone-6.9")])
        #expect(content.previews(locale: "en-US", deviceClassID: "iphone-6.9").isEmpty, "the sidecar is not a preview")
    }

    @Test func readsAVersionWithNoPreviews() throws {
        defer { fixture.remove() }
        let project = try fixture.load()
        try FileManager.default.createDirectory(at: project.versionsURL.appending(path: "1.0"), withIntermediateDirectories: true)
        #expect(try ContentStore.load(version: "1.0", in: project).previewFolder.previews.isEmpty)
    }

    @Test func readsTheVideosOfATreatmentAndNoLanguageCalledPreviews() async throws {
        defer { fixture.remove() }
        let project = try fixture.load()
        let treatment = project.experimentsURL.appending(path: "Fall").appending(path: "Treatment A")
        try await place(Movies.shared.movie("h264.mov"),
                        in: treatment.appending(path: "previews/en-US/iphone-6.9"), as: "01-a.mov")

        let content = ExperimentContentStore.load(in: project)

        #expect(content.previews.keys.map(\.locale) == ["en-US"])
        #expect(content.screenshots.keys.contains { $0.locale == "previews" } == false)
    }
}

// MARK: - Checking previews

struct ValidatorPreviewTests {
    static let config = ProjectConfig(
        bundleID: "b", keyID: "K", issuerID: "I", locales: ["en-US"],
        deviceClasses: [DeviceClass.iPhone69.id, DeviceClass.watchUltra.id]
    )

    static func preview(
        _ name: String = "01-a.mov",
        width: Int = 886, height: Int = 1920, seconds: Double = 20, fps: Double? = 30,
        codec: String = "avc1", bytes: Int = 1000, audio: Bool = true, fragmented: Bool = false,
        poster: String? = nil, readable: Bool = true
    ) -> PreviewFile {
        PreviewFile(
            url: URL(fileURLWithPath: "/tmp/\(name)"), fileName: name, byteCount: bytes,
            pixelWidth: readable ? width : nil, pixelHeight: readable ? height : nil,
            duration: readable ? seconds : nil, frameRate: fps, videoCodec: codec, hasAudio: audio,
            isFragmented: fragmented, posterFrame: poster
        )
    }

    static let refData = AssetLibraryRefData(
        videoSpecs: [AssetLibraryRefData.VideoSpec(
            specId: "v", dimensions: .init(minWidth: 1920, maxWidth: 1920, minHeight: 886, maxHeight: 886),
            frameRates: [.init(minFps: 23, maxFps: 30)], duration: .init(min: "PT15S", max: "PT30S"),
            audioRequired: true, fileExtensions: [".mov", ".mp4", ".m4v"], maxFileSize: 2000
        )],
        placementTypes: [.init(placementTypeId: .appPreview, acceptsAssetCategories: nil, specMappings: [
            .init(placementGroupId: DeviceClass.iPhone69.placementGroup, specs: ["v"])
        ])]
    )

    func kinds(
        _ files: [PreviewFile],
        deviceClass: DeviceClass = .iPhone69,
        refData: AssetLibraryRefData? = refData,
        posterFrames: [String: String] = [:],
        unreadable: Bool = false
    ) -> [Problem.Kind] {
        var folder = PreviewFolder()
        let slot = ScreenshotSlot(locale: "en-US", deviceClassID: deviceClass.id)
        folder.previews[slot] = files
        if posterFrames.isEmpty == false { folder.posterFrames[slot] = posterFrames }
        if unreadable { folder.unreadablePosterFrames.insert(slot) }
        return Validator(config: Self.config, refData: refData).validatePreviewFolder(folder, root: "p").map(\.kind)
    }

    @Test func takesAPreviewThatMatchesTheSpec() {
        #expect(kinds([Self.preview()]).isEmpty)
        #expect(kinds([Self.preview(width: 1920, height: 886)]).isEmpty, "landscape")
    }

    @Test(arguments: [(14.9, false), (15.0, true), (30.0, true), (30.1, false)])
    func checksTheLength(seconds: Double, accepted: Bool) {
        #expect(kinds([Self.preview(seconds: seconds)]) == (accepted ? [] : [.previewWrongLength]))
    }

    @Test(arguments: [(22.0, false), (23.0, true), (30.0, true), (30.4, true), (30.5, false), (60.0, false)])
    func checksTheFrameRate(fps: Double, accepted: Bool) {
        #expect(kinds([Self.preview(fps: fps)]) == (accepted ? [] : [.previewWrongFrameRate]))
    }

    @Test func refusesAWrongSize() {
        #expect(kinds([Self.preview(width: 1080, height: 1920)]) == [.previewWrongSize])
    }

    @Test func refusesAFileOneByteOverTheLimit() {
        #expect(kinds([Self.preview(bytes: 2000)]).isEmpty)
        #expect(kinds([Self.preview(bytes: 2001)]) == [.previewTooLarge])
    }

    @Test func refusesAKindOfFileAndStopsThere() {
        #expect(kinds([Self.preview("01-a.avi", readable: false)]) == [.previewWrongFileType])
    }

    @Test func refusesAFileThatIsNotAMovie() {
        #expect(kinds([Self.preview(readable: false)]) == [.previewUnreadable])
    }

    @Test(arguments: [("01-a.mov", "apch", true), ("01-a.mp4", "apch", false), ("01-a.m4v", "avc1", true),
                      ("01-a.mov", "hvc1", false), ("01-a.mov", "apcn", false)])
    func takesH264EverywhereAndProResOnlyInAMov(name: String, codec: String, accepted: Bool) {
        #expect(kinds([Self.preview(name, codec: codec)]) == (accepted ? [] : [.previewCodecNotAccepted]))
    }

    @Test func warnsAboutAMovieWithNoSoundWhenTheSpecWantsOne() {
        #expect(kinds([Self.preview(audio: false)]) == [.previewHasNoAudio])
        #expect(kinds([Self.preview(width: 886, height: 1920, audio: false)], refData: nil).isEmpty)
    }

    @Test func warnsAboutAFragmentedMovie() {
        #expect(kinds([Self.preview(fps: nil, fragmented: true)]) == [.previewFragmented])
    }

    @Test(arguments: [("00:00:00:00", true), ("00:00:20:00", true), ("00:00:20:01", false), ("00:00:21:00", false),
                      ("5 seconds", false)])
    func checksThePosterFrame(poster: String, accepted: Bool) {
        #expect(kinds([Self.preview(seconds: 20, poster: poster)]) == (accepted ? [] : [.previewPosterFrameNotValid]))
    }

    @Test func warnsAboutAPosterFrameForAFileThatIsNotThere() {
        #expect(kinds([Self.preview()], posterFrames: ["gone.mov": "00:00:01:00"]) == [.previewPosterFrameNamesNoFile])
    }

    @Test func refusesAPosterFrameFileItCannotRead() {
        #expect(kinds([Self.preview()], unreadable: true) == [.previewPosterFramesUnreadable])
    }

    @Test func takesThreePreviewsAndRefusesFour() {
        #expect(kinds((1 ... 3).map { Self.preview("0\($0).mov") }).isEmpty)
        #expect(kinds((1 ... 4).map { Self.preview("0\($0).mov") }) == [.previewsOverLimit])
    }

    @Test func refusesAPreviewForAWatch() {
        #expect(kinds([Self.preview()], deviceClass: .watchUltra) == [.previewDeviceClassTakesNone])
    }

    @Test func warnsAboutPreviewsForADeviceClassTheProjectDoesNotList() {
        #expect(kinds([Self.preview()], deviceClass: .iPad13) == [.deviceClassNotKnown])
    }

    @Test func usesApplesSpecificationWithNoReferenceData() {
        #expect(kinds([Self.preview(width: 886, height: 1920, fps: 30, audio: false)], refData: nil).isEmpty)
        #expect(kinds([Self.preview(width: 1200, height: 1600)], refData: nil) == [.previewWrongSize])
        #expect(kinds([Self.preview(width: 1200, height: 1600)], deviceClass: .iPad13, refData: nil) == [.deviceClassNotKnown])
    }

    @Test(arguments: [("PT15S", 15.0), ("PT30S", 30.0), ("PT1M", 60.0), ("PT1M5S", 65.0), ("PT2.5S", 2.5)])
    func readsAnISODuration(iso: String, seconds: Double) {
        #expect(VideoRules.seconds(iso) == seconds)
    }

    @Test(arguments: ["15", "P1D", "PT", "PT5X", "PT5"])
    func refusesADurationWrittenAnotherWay(iso: String) {
        #expect(VideoRules.seconds(iso) == nil || iso == "PT")
    }
}

// MARK: - Planning and pushing previews

struct PreviewPlanTests {
    let files: LibraryFiles

    static func body(_ transport: StubTransport, at index: Int) async throws -> String {
        try #require(await transport.bodyText(at: index))
    }

    init() throws {
        files = try LibraryFiles()
    }

    /// A video file whose bytes are its name, with a poster frame.
    func video(_ name: String, poster: String? = nil) throws -> PreviewFile {
        let shot = try files.file(name)
        return PreviewFile(url: shot.url, fileName: name, byteCount: shot.byteCount, pixelWidth: 886,
                           pixelHeight: 1920, duration: 20, frameRate: 30, videoCodec: "avc1",
                           hasAudio: true, posterFrame: poster)
    }

    static func placed(_ id: String, asset: String, timeCode: String?) -> RemotePlacement {
        RemotePlacement(
            id: id, locale: "en-US", type: .appPreview, group: Placed.group, state: .parentPrepareForSubmission,
            asset: RemoteLibraryAsset(id: asset, media: .video, fileName: "\(asset).mov",
                                      state: .approved, previewFrameTimeCode: timeCode)
        )
    }

    func record(_ file: PreviewFile, id: String) throws -> AssetRecord {
        var record = AssetRecord()
        try record.record(md5: FileChecksum.md5(of: file.url), AssetRecord.Entry(
            assetID: id, media: .video, fileName: file.fileName, fileSize: file.byteCount, state: .approved
        ))
        return record
    }

    func slot(_ local: [PreviewFile], current: [RemotePlacement], record: AssetRecord) -> LibrarySlot {
        LibraryPlanner.slot(files: local.map(\.libraryFile), current: current, record: record,
                            group: Placed.group, type: .appPreview)
    }

    @Test func leavesAPreviewWithTheSamePosterFrame() throws {
        defer { files.remove() }
        let one = try video("01.mov", poster: "00:00:02:00")
        let slot = try slot([one], current: [Self.placed("p1", asset: "v1", timeCode: "00:00:02:00")],
                            record: record(one, id: "v1"))
        #expect(slot.isUnchanged)
    }

    @Test func changesOnlyThePosterFrame() throws {
        defer { files.remove() }
        let one = try video("01.mov", poster: "00:00:04:00")
        let slot = try slot([one], current: [Self.placed("p1", asset: "v1", timeCode: "00:00:02:00")],
                            record: record(one, id: "v1"))

        #expect(slot.posterFrames == ["v1": "00:00:04:00"])
        #expect(slot.isUnchanged == false)
        #expect(slot.uploads == 0)
        #expect(slot.toRemove.isEmpty)
    }

    @Test func leavesApplesPosterFrameWhenTheProjectNamesNone() throws {
        defer { files.remove() }
        let one = try video("01.mov")
        let slot = try slot([one], current: [Self.placed("p1", asset: "v1", timeCode: "00:00:02:00")],
                            record: record(one, id: "v1"))
        #expect(slot.isUnchanged)
    }

    @Test func setsTheOnlyPosterFrameAndNothingElse() async throws {
        defer { files.remove() }
        let one = try video("01.mov", poster: "00:00:04:00")
        let record = try record(one, id: "v1")
        let current = [Self.placed("p1", asset: "v1", timeCode: "00:00:02:00"),
                       Self.placed("p2", asset: "v2", timeCode: nil)]
        let two = try video("02.mov")
        var both = record
        try both.record(md5: FileChecksum.md5(of: two.url), AssetRecord.Entry(
            assetID: "v2", media: .video, fileName: "02.mov", fileSize: two.byteCount, state: .approved
        ))
        let target = LibraryPusher.Target(
            id: "t", label: "en-US", deviceClassID: "iphone-6.9", parent: .versionLocalization(id: "l"),
            files: [one, two].map(\.libraryFile), slot: slot([one, two], current: current, record: both)
        )
        let transport = StubTransport([.ok(#"{"data":{"type":"appAssetLibraryVideos","id":"v1","attributes":{}}}"#)])

        let pushed = try await LibraryPusher(client: ASCClient.stubbed(transport: transport), poll: .immediate)
            .push([target], libraryID: "lib", record: both, saveRecord: { _ in })

        #expect(pushed.result.isCompleteSuccess)
        #expect(await LibraryPusherTests.calls(transport) == ["PATCH /v1/appAssetLibraryVideos/v1"])
        let body = try await Self.body(transport, at: 0)
        #expect(body.contains("00:00:04:00"))
    }

    @Test func uploadsANewVideoWithItsPosterFrameAndPlacesItAsAVideo() async throws {
        defer { files.remove() }
        let one = try video("01.mov", poster: "00:00:03:00")
        let target = LibraryPusher.Target(
            id: "t", label: "en-US", deviceClassID: "iphone-6.9", parent: .versionLocalization(id: "l"),
            files: [one.libraryFile], slot: slot([one], current: [], record: AssetRecord())
        )
        let transport = StubTransport([
            .ok("""
            {"data":{"type":"appAssetLibraryVideos","id":"v9","attributes":{"state":"AWAITING_UPLOAD",
              "uploadOperations":[{"method":"PUT","url":"https://blob.example.test/v9","length":1,"offset":0,
              "requestHeaders":[]}]}}}
            """),
            .ok(""),
            .ok(#"{"data":{"type":"appAssetLibraryVideos","id":"v9","attributes":{}}}"#),
            .ok(#"{"data":[{"type":"appAssetLibraryVideos","id":"v9","attributes":{"state":"PREPARE_FOR_SUBMISSION"}}]}"#),
            LibraryReply.placement("p9")
        ])

        let pushed = try await LibraryPusher(client: ASCClient.stubbed(transport: transport), poll: .immediate)
            .push([target], libraryID: "lib", record: AssetRecord(), saveRecord: { _ in })

        #expect(pushed.result.isCompleteSuccess)
        let calls = await LibraryPusherTests.calls(transport)
        #expect(calls == [
            "POST /v1/appAssetLibraryVideos", "PUT /v9", "PATCH /v1/appAssetLibraryVideos/v9",
            "GET /v1/appAssetLibraries/lib/videos", "POST /v1/appAssetLibraryPlacements"
        ])
        let reserve = try await Self.body(transport, at: 0)
        #expect(reserve.contains("00:00:03:00"))
        let place = try await Self.body(transport, at: 4)
        #expect(place.contains(#""video""#) && place.contains("APP_PREVIEW"))
    }
}

// MARK: - Previews in the plan of a version

struct PreviewVersionPlanTests {
    let fixture: FixtureProject

    init() throws {
        fixture = try FixtureProject()
        try fixture.writeConfig(ProjectConfig(
            bundleID: "b", keyID: "K", issuerID: "I", locales: ["en-US"],
            deviceClasses: [DeviceClass.iPhone69.id, DeviceClass.watchUltra.id]
        ))
        try fixture.writeCopy(AppInformation(locale: "en-US", status: .approved, fields: AppInformation.Fields(
            name: "Stocked", subtitle: "Pantry", keywords: "pantry", description: "Words.",
            whatsNew: "New.", supportUrl: "https://example.com/support",
            privacyPolicyUrl: "https://example.com/privacy"
        )))
    }

    func listing(state: AppVersionState = .prepareForSubmission) -> RemoteListing {
        RemoteListing(
            appID: "app1", appName: "Demo", bundleID: "b", appInfoID: nil, appInfoState: nil,
            versionID: "v1", versionString: "1.0", versionState: state, appInfoLocalizations: [:],
            versionLocalizations: ["en-US": RemoteLocalization(id: "l-en", locale: "en-US", values: [:])],
            screenshotSets: []
        )
    }

    func content(previewIn deviceClass: DeviceClass) throws -> VersionContent {
        let project = try fixture.load()
        let folder = project.previewsURL(version: "1.0", locale: "en-US", deviceClassID: deviceClass.id)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("a movie".utf8).write(to: folder.appending(path: "01-a.mov"))
        return try ContentStore.load(version: "1.0", in: project)
    }

    @Test func plansAPreviewForAnIPhone() throws {
        defer { fixture.remove() }
        let plan = try Planner.plan(local: content(previewIn: .iPhone69), config: fixture.load().config,
                                    remote: listing(), record: AssetRecord())

        #expect(plan.previewPlans.map(\.deviceClass) == [.iPhone69])
        #expect(plan.hasScreenshotChanges)
        #expect(ChangePlanFormatter.lines(for: plan).contains("App previews:"))
        #expect(PushSession.targets(in: plan, listing: listing()).map(\.id) == ["en-US|iphone-6.9|previews"])
    }

    @Test func plansNoPreviewForAWatch() throws {
        defer { fixture.remove() }
        let plan = try Planner.plan(local: content(previewIn: .watchUltra), config: fixture.load().config,
                                    remote: listing(), record: AssetRecord())
        #expect(plan.previewPlans.isEmpty)
    }

    @Test func blocksAPreviewOnAVersionThatTakesNoImages() throws {
        defer { fixture.remove() }
        let plan = try Planner.plan(local: content(previewIn: .iPhone69), config: fixture.load().config,
                                    remote: listing(state: .readyForDistribution), record: AssetRecord())
        #expect(plan.blocked(.screenshots).isEmpty == false)
    }
}

struct PreviewExperimentPlanTests {
    @Test func plansAndPushesTheVideosOfATreatment() throws {
        let files = try LibraryFiles()
        defer { files.remove() }
        let shot = try files.file("01.mov")
        let video = PreviewFile(url: shot.url, fileName: "01.mov", byteCount: shot.byteCount)
        let config = ProjectConfig(bundleID: "b", keyID: "K", issuerID: "I", locales: ["en-US"],
                                   deviceClasses: [DeviceClass.iPhone69.id])
        let local = ExperimentContent(previews: [
            ExperimentSlot(experiment: "Fall", treatment: "Treatment A", locale: "en-US",
                           deviceClassID: DeviceClass.iPhone69.id): [video]
        ])

        let plan = ExperimentPlanner.plan(
            local: local, config: config,
            remote: LibraryExperimentPlanTests.remote(placements: []), record: AssetRecord()
        )

        #expect(plan.previewSets.count == 1)
        #expect(plan.hasChanges)
        #expect(PushSession.targets(in: plan).map(\.parent) == [.treatmentLocalization(id: "tl-en")])
        #expect(PushSession.targets(in: plan).first?.files.first?.media == .video)
    }
}
