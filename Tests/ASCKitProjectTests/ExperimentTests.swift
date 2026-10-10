import ASCKitAPI
import Foundation
import Testing
@testable import ASCKitProject

final class ExperimentTests {
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

    var remote: RemoteExperiments {
        RemoteExperiments(appID: "app1", experiments: [
            RemoteExperiment(
                id: "e1", name: "Bigger buttons", state: .prepareForSubmission, platform: .ios,
                treatments: [RemoteTreatment(id: "t1", name: "Treatment A", localizations: [
                    RemoteTreatmentLocalization(id: "tloc-en", locale: "en-US"),
                    RemoteTreatmentLocalization(id: "tloc-de", locale: "de-DE")
                ])]
            )
        ])
    }

    /// The draft, and a test in review that has a lower id and the same name.
    var remoteWithLockedTest: RemoteExperiments {
        RemoteExperiments(appID: "app1", experiments: remote.experiments + [
            RemoteExperiment(
                id: "a0", name: "Bigger buttons", state: .inReview, platform: .ios,
                treatments: [RemoteTreatment(id: "t0", name: "Treatment A", localizations: [
                    RemoteTreatmentLocalization(id: "tloc-old", locale: "en-US")
                ])]
            )
        ])
    }

    func slot(_ locale: String = "en-US") -> ExperimentSlot {
        ExperimentSlot(
            experiment: "Bigger buttons", treatment: "Treatment A",
            locale: locale, deviceClassID: deviceClass.id
        )
    }

    func writeImage(_ name: String, in slot: ExperimentSlot, alpha: Bool = false) throws {
        let directory = project.experimentURL(
            experiment: slot.experiment, treatment: slot.treatment,
            locale: slot.locale, deviceClassID: slot.deviceClassID
        )
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try PNGWriter.write(
            to: directory.appending(path: name), width: 1320, height: 2868,
            hasAlpha: alpha, seed: name
        )
    }

    // MARK: - Folder names

    @Test func keepsANameReadableAndRemovesWhatAPathCannotHold() {
        #expect(ExperimentFolders.folderName(for: "Bigger buttons") == "Bigger buttons")
        #expect(ExperimentFolders.folderName(for: "A/B: test") == "A-B- test")
        #expect(ExperimentFolders.folderName(for: "  ..  ") == "untitled")
    }

    @Test func tellsTwoTreatmentsOfOneNameApart() {
        let names = ExperimentFolders.folderNames(for: [("id-aaaa1", "Same"), ("id-bbbb2", "Same")])
        #expect(names["id-aaaa1"] == "Same")
        #expect(names["id-bbbb2"] == "Same (bbb2)")
    }

    /// The locked test has the lower id, and it still does not take the
    /// folder that holds the draft's images.
    @Test func namesTheEditableTestFirst() {
        let names = ExperimentFolders.folderNames(for: remoteWithLockedTest)
        #expect(names["e1"] == "Bigger buttons")
        #expect(names["a0"] == "Bigger buttons (a0)")
    }

    // MARK: - Reading

    @Test func makesAFolderForEachLanguageOfEachTreatment() throws {
        let made = try ExperimentFolders.scaffold(remote, in: project)

        #expect(made.count == 2)
        #expect(FileManager.default.fileExists(
            atPath: project.experimentURL(
                experiment: "Bigger buttons", treatment: "Treatment A",
                locale: "de-DE", deviceClassID: deviceClass.id
            ).path
        ))
        #expect(try ExperimentFolders.scaffold(remote, in: project).isEmpty)
    }

    @Test func makesNoFolderForALockedTest() throws {
        let made = try ExperimentFolders.scaffold(remoteWithLockedTest, in: project)

        #expect(made.count == 2)
        #expect(made.allSatisfy { $0.path.contains("Bigger buttons (a0)") == false })
    }

    // MARK: - Planning

    @Test func plansAnUploadForANewImage() throws {
        try writeImage("01-a-iPhone-6.9-en_US.png", in: slot())
        let content = ExperimentContentStore.load(in: project)

        let plan = ExperimentPlanner.plan(local: content, config: project.config, remote: remote)

        let set = try #require(plan.sets.first)
        #expect(plan.sets.count == 1)
        #expect(set.treatmentLocalizationID == "tloc-en")
        #expect(set.action == .replace(removing: 0, adding: 1))
        #expect(plan.imagesToAdd == 1)
    }

    @Test func leavesAMatchingSetAlone() throws {
        try writeImage("01-a-iPhone-6.9-en_US.png", in: slot())
        let content = ExperimentContentStore.load(in: project)
        let file = try #require(content.screenshots(in: slot()).first)

        var draft = remote
        var record = AssetRecord()
        try record.record(md5: FileChecksum.md5(of: file.url), AssetRecord.Entry(
            assetID: "a1", media: .image, fileName: file.fileName, fileSize: file.byteCount, state: .approved
        ))
        let placement = RemotePlacement(
            id: "p1", locale: "en-US", type: .appScreenshot, group: deviceClass.placementGroup,
            state: .parentPrepareForSubmission,
            asset: RemoteLibraryAsset(id: "a1", media: .image, fileName: file.fileName, state: .approved)
        )
        let treatment = draft.experiments[0].treatments[0]
        draft = RemoteExperiments(appID: "app1", experiments: [RemoteExperiment(
            id: "e1", name: "Bigger buttons", state: .prepareForSubmission, platform: .ios,
            treatments: [RemoteTreatment(id: "t1", name: treatment.name, localizations: [
                RemoteTreatmentLocalization(id: "tloc-en", locale: "en-US", placements: [placement])
            ])]
        )])

        let plan = ExperimentPlanner.plan(local: content, config: project.config, remote: draft, record: record)
        #expect(plan.hasChanges == false)
    }

    /// ASCKit never makes a language of a treatment, so images for one that
    /// is not there go nowhere and the plan says so.
    @Test func reportsImagesWithNoPlaceToGo() throws {
        try writeImage("01-a-iPhone-6.9-fr_FR.png", in: slot("fr-FR"))
        try writeImage("01-a-iPhone-6.9-en_US.png", in: ExperimentSlot(
            experiment: "Old test", treatment: "Treatment A", locale: "en-US", deviceClassID: deviceClass.id
        ))
        let content = ExperimentContentStore.load(in: project)

        let plan = ExperimentPlanner.plan(local: content, config: project.config, remote: remote)

        #expect(plan.sets.isEmpty)
        let reasons = Dictionary(uniqueKeysWithValues: plan.unplaced.map { ($0.slot.experiment + $0.slot.locale, $0.reason) })
        #expect(reasons["Bigger buttonsfr-FR"] == .noLanguage)
        #expect(reasons["Old testen-US"] == .noDraftExperiment)
    }

    @Test func plansNothingForALockedTest() throws {
        let locked = ExperimentSlot(
            experiment: "Bigger buttons (a0)", treatment: "Treatment A", locale: "en-US", deviceClassID: deviceClass.id
        )
        try writeImage("01-a-iPhone-6.9-en_US.png", in: locked)
        try writeImage("01-a-iPhone-6.9-en_US.png", in: slot())
        let content = ExperimentContentStore.load(in: project)

        let plan = ExperimentPlanner.plan(local: content, config: project.config, remote: remoteWithLockedTest)

        #expect(plan.sets.map(\.experimentID) == ["e1"])
        #expect(plan.unplaced.map(\.reason) == [.locked(state: .inReview)])
    }

    // MARK: - Writing

    @Test func putsATreatmentSetInTheOrderItWasGiven() throws {
        try writeImage("01-a-iPhone-6.9-en_US.png", in: slot())
        try writeImage("02-b-iPhone-6.9-en_US.png", in: slot())
        try writeImage("03-c-iPhone-6.9-en_US.png", in: slot())

        let files = try ContentWriter.reorderScreenshots(
            order: ["03-c-iPhone-6.9-en_US.png", "01-a-iPhone-6.9-en_US.png", "02-b-iPhone-6.9-en_US.png"],
            locale: "en-US", deviceClass: deviceClass, at: slot().place, in: project
        )

        #expect(files.map(\.fileName) == [
            "01-c-iPhone-6.9-en_US.png", "02-a-iPhone-6.9-en_US.png", "03-b-iPhone-6.9-en_US.png"
        ])
    }

    @Test func refusesATreatmentOrderThatLeavesAnImageOut() throws {
        try writeImage("01-a-iPhone-6.9-en_US.png", in: slot())
        try writeImage("02-b-iPhone-6.9-en_US.png", in: slot())

        #expect(throws: ContentWriteError.self) {
            try ContentWriter.reorderScreenshots(
                order: ["02-b-iPhone-6.9-en_US.png"], locale: "en-US", deviceClass: self.deviceClass,
                at: self.slot().place, in: self.project
            )
        }
        let files = ExperimentContentStore.load(in: project).screenshots(in: slot())
        #expect(files.map(\.fileName) == ["01-a-iPhone-6.9-en_US.png", "02-b-iPhone-6.9-en_US.png"])
    }

    /// A file named under an older rule gets its name put right by a reorder,
    /// the same as in a version.
    @Test func namesATreatmentSetByTheRuleWhenItMoves() throws {
        try writeImage("01-a.png", in: slot())
        try writeImage("02-b.png", in: slot())

        let files = try ContentWriter.reorderScreenshots(
            order: ["02-b.png", "01-a.png"], locale: "en-US", deviceClass: deviceClass, at: slot().place, in: project
        )

        #expect(files.map(\.fileName) == ["01-b-iPhone-6.9-en_US.png", "02-a-iPhone-6.9-en_US.png"])
    }

    // MARK: - Emptied on purpose

    @Test func marksASetEmptiedWhenTheLastImageGoes() throws {
        try writeImage("01-a-iPhone-6.9-en_US.png", in: slot())

        try ContentWriter.removeScreenshots(
            named: ["01-a-iPhone-6.9-en_US.png"], locale: "en-US", deviceClass: deviceClass, at: slot().place, in: project
        )

        #expect(ExperimentContentStore.load(in: project).emptied == [slot()])
    }

    @Test func takesTheMarkOffWhenAnImageArrives() throws {
        try ContentWriter.removeAllScreenshots(locale: "en-US", deviceClass: deviceClass, at: slot().place, in: project)
        #expect(ExperimentContentStore.load(in: project).emptied == [slot()])

        let incoming = fixture.rootURL.appending(path: "incoming")
        try FileManager.default.createDirectory(at: incoming, withIntermediateDirectories: true)
        try PNGWriter.write(
            to: incoming.appending(path: "hero.png"), width: 1320, height: 2868, hasAlpha: false, seed: "h"
        )
        try ContentWriter.addScreenshots(
            from: [incoming.appending(path: "hero.png")], locale: "en-US", deviceClass: deviceClass,
            at: slot().place, in: project
        )

        #expect(ExperimentContentStore.load(in: project).emptied.isEmpty)
    }

    /// A read writes no image files. The empty folder it makes must not take
    /// App Store Connect's images off.
    @Test func leavesTheImagesOfAnEmptySetAloneUntilItIsEmptiedOnPurpose() throws {
        try ExperimentFolders.scaffold(remote, in: project)
        let placement = RemotePlacement(
            id: "p1", locale: "en-US", type: .appScreenshot, group: deviceClass.placementGroup,
            state: .parentPrepareForSubmission,
            asset: RemoteLibraryAsset(id: "a1", media: .image, fileName: "01-a.png", state: .approved)
        )
        let treatment = remote.experiments[0].treatments[0]
        let held = RemoteExperiments(appID: "app1", experiments: [RemoteExperiment(
            id: "e1", name: "Bigger buttons", state: .prepareForSubmission, platform: .ios,
            treatments: [RemoteTreatment(id: "t1", name: treatment.name, localizations: [
                RemoteTreatmentLocalization(id: "tloc-en", locale: "en-US", placements: [placement])
            ])]
        )])

        let before = ExperimentPlanner.plan(
            local: ExperimentContentStore.load(in: project), config: project.config, remote: held
        )
        #expect(before.sets.isEmpty)

        try ContentWriter.removeAllScreenshots(locale: "en-US", deviceClass: deviceClass, at: slot().place, in: project)
        let after = ExperimentPlanner.plan(
            local: ExperimentContentStore.load(in: project), config: project.config, remote: held
        )
        #expect(after.sets.map(\.action) == [.replace(removing: 1, adding: 0)])
    }

    // MARK: - Checking

    @Test func refusesAnAlphaChannel() throws {
        try writeImage("01-a-iPhone-6.9-en_US.png", in: slot(), alpha: true)
        let content = ExperimentContentStore.load(in: project)

        let problems = Validator(config: project.config).validate(content)

        #expect(problems.contains { $0.kind == .screenshotHasAlpha })
    }

    // MARK: - The inbox

    @Test func filesAnInboxImageIntoItsTreatment() throws {
        try ExperimentFolders.scaffold(remote, in: project)
        let waiting = ExperimentInbox.url(in: project)
            .appending(path: "Bigger buttons").appending(path: "Treatment A")
        try FileManager.default.createDirectory(at: waiting, withIntermediateDirectories: true)
        try PNGWriter.write(
            to: waiting.appending(path: "03-shopping-iPhone-6.9-de_DE.png"),
            width: 1320, height: 2868, hasAlpha: false, seed: "x"
        )

        let plan = ExperimentInbox.plan(in: project)
        #expect(plan.refusals.isEmpty)
        #expect(plan.arrivals.first?.slot == slot("de-DE"))

        // The version inbox leaves it alone.
        #expect(Inbox.waiting(in: project).isEmpty)

        let outcome = try ExperimentInbox.file(plan, in: project)
        #expect(outcome.filed == 1)
        let filed = ExperimentContentStore.load(in: project).screenshots(in: slot("de-DE"))
        #expect(filed.map(\.fileName) == ["01-shopping-iPhone-6.9-de_DE.png"])
    }

    @Test func refusesAnInboxImageOutsideATreatment() throws {
        let waiting = ExperimentInbox.url(in: project)
        try FileManager.default.createDirectory(at: waiting, withIntermediateDirectories: true)
        try PNGWriter.write(
            to: waiting.appending(path: "03-shopping-iPhone-6.9-en_US.png"),
            width: 1320, height: 2868, hasAlpha: false, seed: "y"
        )
        let plan = ExperimentInbox.plan(in: project)
        #expect(plan.arrivals.isEmpty)
        #expect(plan.refusals.count == 1)
    }

    /// The folder of the locked test exists on disk, and it is still refused.
    @Test func refusesAnInboxImageForALockedTest() throws {
        try writeImage("01-a-iPhone-6.9-en_US.png", in: ExperimentSlot(
            experiment: "Bigger buttons (a0)", treatment: "Treatment A", locale: "en-US", deviceClassID: deviceClass.id
        ))
        let waiting = ExperimentInbox.url(in: project)
            .appending(path: "Bigger buttons (a0)").appending(path: "Treatment A")
        try FileManager.default.createDirectory(at: waiting, withIntermediateDirectories: true)
        try PNGWriter.write(
            to: waiting.appending(path: "03-shopping-iPhone-6.9-en_US.png"),
            width: 1320, height: 2868, hasAlpha: false, seed: "z"
        )

        let fromRemote = ExperimentInbox.plan(in: project, remote: remoteWithLockedTest)
        let fromSnapshot = ExperimentInbox.plan(in: project, snapshot: ExperimentSnapshot(remoteWithLockedTest))

        for plan in [fromRemote, fromSnapshot] {
            #expect(plan.arrivals.isEmpty)
            #expect(plan.refusals.first?.reason.contains("IN_REVIEW") == true)
        }
    }

    @Test func keepsWhatTheReadFoundInACache() throws {
        try ExperimentSnapshotStore.save(ExperimentSnapshot(remoteWithLockedTest), in: project)
        let loaded = try #require(ExperimentSnapshotStore.load(in: project))
        let draft = try #require(loaded.experiments.first { $0.folder == "Bigger buttons" })
        #expect(draft.treatments.first?.locales == ["de-DE", "en-US"])
        #expect(draft.state == "PREPARE_FOR_SUBMISSION")
        #expect(draft.isEditable)
        let locked = try #require(loaded.experiments.first { $0.folder == "Bigger buttons (a0)" })
        #expect(locked.state == "IN_REVIEW")
        #expect(locked.isEditable == false)
    }

    /// A cache from before 0.4.0 held only draft tests and no state.
    @Test func readsAnOldCacheAsEditable() throws {
        let json = """
        {"readOn":"2026-10-01T10:00:00Z","experiments":[{"name":"Bigger buttons","folder":"Bigger buttons",
          "platform":"IOS","treatments":[{"name":"Treatment A","folder":"Treatment A","locales":["en-US"]}]}]}
        """
        let url = ExperimentSnapshotStore.url(in: project)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(json.utf8).write(to: url)

        let loaded = try #require(ExperimentSnapshotStore.load(in: project))
        #expect(loaded.experiments.first?.isEditable == true)
        #expect(loaded.experiments.first?.state == nil)
    }
}
