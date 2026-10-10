import ASCKitAPI
import Foundation
import Testing
@testable import ASCKitProject

/// A language of a treatment with no screenshots, where another language of
/// the treatment has them.
final class TreatmentLanguageCheckTests {
    let fixture: FixtureProject
    let project: Project
    let deviceClass = DeviceClass.iPhone69

    init() throws {
        fixture = try FixtureProject()
        let config = ProjectConfig(
            bundleID: "com.example.Demo",
            keyID: "ABC123",
            issuerID: "issuer",
            sourceLocale: "en-US",
            locales: ["en-US", "de-DE"],
            deviceClasses: [DeviceClass.iPhone69.id]
        )
        let url = try fixture.writeConfig(config)
        project = Project(configURL: url, config: config)
    }

    deinit {
        fixture.remove()
    }

    func remote(state: ExperimentState = .prepareForSubmission, held: [RemotePlacement] = []) -> RemoteExperiments {
        RemoteExperiments(appID: "app1", experiments: [
            RemoteExperiment(
                id: "e1", name: "Bigger buttons", state: state, platform: .ios,
                treatments: [RemoteTreatment(id: "t1", name: "Treatment A", localizations: [
                    RemoteTreatmentLocalization(id: "tloc-en", locale: "en-US"),
                    RemoteTreatmentLocalization(
                        id: "tloc-de", locale: "de-DE", placements: held.filter { $0.locale == "de-DE" }
                    )
                ])]
            )
        ])
    }

    func slot(_ locale: String) -> ExperimentSlot {
        ExperimentSlot(experiment: "Bigger buttons", treatment: "Treatment A", locale: locale, deviceClassID: deviceClass.id)
    }

    func writeImage(in slot: ExperimentSlot) throws {
        let directory = project.experimentURL(
            experiment: slot.experiment, treatment: slot.treatment,
            locale: slot.locale, deviceClassID: slot.deviceClassID
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try PNGWriter.write(
            to: directory.appending(path: "01-a-iPhone-6.9-\(slot.locale.replacingOccurrences(of: "-", with: "_")).png"),
            width: 1320, height: 2868, hasAlpha: false, seed: slot.locale
        )
    }

    func missing(_ remote: RemoteExperiments?) -> [Problem] {
        Validator(config: project.config)
            .validate(ExperimentContentStore.load(in: project), snapshot: remote.map { ExperimentSnapshot($0) })
            .filter { $0.kind == .treatmentScreenshotsMissing }
    }

    @Test func warnsForALanguageWithNoScreenshots() throws {
        try ExperimentFolders.scaffold(remote(), in: project)
        try writeImage(in: slot("en-US"))

        let problems = missing(remote())

        let problem = try #require(problems.first)
        #expect(problems.count == 1)
        #expect(problem.severity == .warning)
        #expect(problem.locale == "de-DE")
        #expect(problem.deviceClassID == deviceClass.id)
        #expect(problem.path == slot("de-DE").place.screenshotsPath(
            config: project.config, locale: "de-DE", deviceClassID: deviceClass.id
        ))
    }

    /// A treatment that tests only the icon has no screenshots anywhere.
    @Test func saysNothingWhenNoLanguageHasScreenshots() throws {
        try ExperimentFolders.scaffold(remote(), in: project)

        #expect(missing(remote()).isEmpty)
    }

    @Test func countsTheScreenshotsAppStoreConnectHolds() throws {
        try writeImage(in: slot("en-US"))
        let held = RemotePlacement(
            id: "p1", locale: "de-DE", type: .appScreenshot, group: deviceClass.placementGroup,
            state: .parentPrepareForSubmission,
            asset: RemoteLibraryAsset(id: "a1", media: .image, fileName: "01-a.png", state: .approved)
        )

        #expect(missing(remote(held: [held])).isEmpty)
    }

    @Test func saysNothingForASetEmptiedOnPurpose() throws {
        try writeImage(in: slot("en-US"))
        try ContentWriter.removeAllScreenshots(locale: "de-DE", deviceClass: deviceClass, at: slot("de-DE").place, in: project)

        #expect(missing(remote()).isEmpty)
    }

    @Test func checksNothingForALockedTestOrWithoutARead() throws {
        try writeImage(in: slot("en-US"))

        #expect(missing(remote(state: .inReview)).isEmpty)
        #expect(missing(nil).isEmpty)
    }

    @Test func readsACacheFromBeforeTheHeldScreenshots() throws {
        let json = """
        {"readOn":"2026-10-01T00:00:00Z","experiments":[{"name":"Bigger buttons","folder":"Bigger buttons",\
        "platform":"IOS","state":"PREPARE_FOR_SUBMISSION","isEditable":true,\
        "treatments":[{"name":"Treatment A","folder":"Treatment A","locales":["de-DE","en-US"]}]}]}
        """
        let snapshot = try ProjectJSON.decoder(datesAsISO8601: true)
            .decode(ExperimentSnapshot.self, from: Data(json.utf8))

        #expect(snapshot.experiments.first?.treatments.first?.heldScreenshots.isEmpty == true)
    }
}
