import ASCKitAPI
import ASCKitTestSupport
import Foundation
import Testing
@testable import ASCKitProject

/// App Store Connect copies the listing into a new version. The folder for it
/// has to start as the same copy, or the first plan removes every screenshot.
final class VersionSeedTests {
    let fixture: FixtureProject

    init() throws {
        fixture = try FixtureProject()
        try fixture.writeConfig(ProjectConfig(
            bundleID: "com.example.Demo",
            keyID: "ABC123",
            issuerID: "issuer",
            sourceLocale: "en-US",
            locales: ["en-US", "de-DE"],
            deviceClasses: [DeviceClass.iPhone69.id]
        ))
        for locale in ["en-US", "de-DE"] {
            try fixture.writeCopy(AppInformation(locale: locale, status: .approved))
        }
        for name in ["01-hero.png", "02-list.png"] {
            try fixture.writeScreenshot(
                locale: "en-US", deviceClassID: DeviceClass.iPhone69.id,
                named: name, width: 1290, height: 2796
            )
        }
    }

    deinit {
        fixture.remove()
    }

    /// The images of an older folder as placements of library assets, with
    /// the record that names each asset's bytes written to the project.
    func remoteShots(locale: String) throws -> [RemotePlacement] {
        let project = try fixture.load()
        let content = try ContentStore.load(version: fixture.version, in: project)
        var record = try AssetRecordStore.load(in: project)
        let placements = try content.screenshots(locale: locale, deviceClassID: DeviceClass.iPhone69.id).map { file in
            let id = "\(locale)-\(file.fileName)"
            try record.record(md5: FileChecksum.md5(of: file.url), AssetRecord.Entry(
                assetID: id, media: .image, fileName: file.fileName, fileSize: file.byteCount, state: .approved
            ))
            return Self.placement(id, locale: locale)
        }
        try AssetRecordStore.save(record, in: project)
        return placements
    }

    static func placement(_ assetID: String, locale: String) -> RemotePlacement {
        RemotePlacement(
            id: "p-\(assetID)", locale: locale, type: .appScreenshot,
            group: DeviceClass.iPhone69.placementGroup, state: .parentApproved,
            asset: RemoteLibraryAsset(id: assetID, media: .image, state: .approved)
        )
    }

    /// The same placements, on another language's page.
    func on(_ locale: String, _ placements: [RemotePlacement]) -> [RemotePlacement] {
        placements.map {
            RemotePlacement(id: "\(locale)-\($0.id)", locale: locale, type: $0.type, group: $0.group,
                            state: $0.state, asset: $0.asset)
        }
    }

    /// What a plan says about a folder against these placements.
    func isUnchanged(_ files: [ScreenshotFile], _ placements: [RemotePlacement]) throws -> Bool {
        try LibraryPlanner.slot(
            files: files.map(\.libraryFile), current: placements, record: AssetRecordStore.load(in: fixture.load()),
            group: DeviceClass.iPhone69.placementGroup, type: .appScreenshot
        ).isUnchanged
    }

    func listing(placements: [RemotePlacement]) -> RemoteListing {
        .fixture(
            versionID: "v2",
            versionString: "2.0",
            appInfoLocalizations: [
                "en-US": RemoteLocalization(id: "i1", locale: "en-US", values: ["name": "Demo", "subtitle": "Lists"]),
                "fr-FR": RemoteLocalization(id: "i2", locale: "fr-FR", values: ["name": "Démo"])
            ],
            versionLocalizations: [
                "en-US": RemoteLocalization(id: "v1", locale: "en-US", values: ["keywords": "pantry", "whatsNew": ""]),
                "de-DE": RemoteLocalization(id: "v2", locale: "de-DE", values: [:]),
                "es-ES": RemoteLocalization(id: "v3", locale: "es-ES", values: [:]),
                "es-MX": RemoteLocalization(id: "v4", locale: "es-MX", values: [:])
            ],
            placements: placements
        )
    }

    @Test func writesTheWordsOfEveryListedLanguage() throws {
        let project = try fixture.load()
        let outcome = try VersionSeed.seed(version: "2.0", from: listing(placements: []), in: project)
        let content = try ContentStore.load(version: "2.0", in: project)
        let english = try #require(content.appInformation["en-US"])

        #expect(outcome.written == ["de-DE", "en-US"])
        #expect(english.fields[.subtitle] == "Lists")
        #expect(english.fields[.keywords] == "pantry")
        #expect(english.fields[.whatsNew] == nil)
        // French is on App Store Connect and not in the project.
        #expect(content.appInformation["fr-FR"] == nil)
    }

    /// Same bytes in the same order, so the planner leaves the set alone.
    @Test func copiesTheScreenshotsAnOlderFolderHolds() throws {
        let project = try fixture.load()
        let shots = try Array(remoteShots(locale: "en-US").reversed())

        let outcome = try VersionSeed.seed(version: "2.0", from: listing(placements: shots), in: project)
        let files = try ContentStore.load(version: "2.0", in: project)
            .screenshots(locale: "en-US", deviceClassID: DeviceClass.iPhone69.id)

        #expect(outcome.copied.map(\.locale) == ["en-US"])
        #expect(outcome.missing.isEmpty)
        #expect(try isUnchanged(files, shots))
    }

    /// A set with one unknown image is left empty and named, rather than half
    /// copied.
    @Test func namesASetWithAnImageNoFolderHolds() throws {
        let project = try fixture.load()
        var shots = try remoteShots(locale: "en-US")
        shots.append(Self.placement("added-on-the-website", locale: "en-US"))

        let outcome = try VersionSeed.seed(version: "2.0", from: listing(placements: shots), in: project)
        let files = try ContentStore.load(version: "2.0", in: project)
            .screenshots(locale: "en-US", deviceClassID: DeviceClass.iPhone69.id)

        #expect(outcome.missing.map(\.count) == [3])
        #expect(outcome.copied.isEmpty)
        #expect(files.isEmpty)
    }

    /// es-ES and es-MX often hold one picture. A match in another language is
    /// still the same bytes.
    @Test func findsAnImageInAnotherLanguage() throws {
        let project = try fixture.load()
        let shots = try on("de-DE", remoteShots(locale: "en-US"))

        let outcome = try VersionSeed.seed(version: "2.0", from: listing(placements: shots), in: project)
        let files = try ContentStore.load(version: "2.0", in: project)
            .screenshots(locale: "de-DE", deviceClassID: DeviceClass.iPhone69.id)

        #expect(outcome.copied.map(\.locale) == ["de-DE"])
        #expect(files.allSatisfy { $0.fileName.contains("de_DE") })
    }

    // MARK: - A language that copies the language beside it

    /// Two Spanishes. The older folder holds a set for each, with different
    /// pictures, and `es-ES` is set to copy `es-MX`.
    ///
    /// The `es-MX` set is the newer one, with the date said out loud. A copy
    /// keeps the date of the file it came from, so the new folder reads the
    /// same way.
    func makeSpanishProject() throws {
        try fixture.writeConfig(ProjectConfig(
            bundleID: "com.example.Demo",
            keyID: "ABC123",
            issuerID: "issuer",
            sourceLocale: "en-US",
            locales: ["en-US", "es-ES", "es-MX"],
            deviceClasses: [DeviceClass.iPhone69.id],
            copiesScreenshotsFrom: ["es-ES": [DeviceClass.iPhone69.id: "es-MX"]]
        ))
        let written = ["es-ES": 1_700_000_000.0, "es-MX": 1_750_000_000.0]
        for (locale, seconds) in written {
            try fixture.writeScreenshot(
                locale: locale, deviceClassID: DeviceClass.iPhone69.id,
                named: "01-hero.png", width: 1290, height: 2796
            )
            try fixture.setModified(
                locale: locale, deviceClassID: DeviceClass.iPhone69.id,
                to: Date(timeIntervalSince1970: seconds)
            )
        }
    }

    func spanishSet(_ locale: String, holding shots: [RemotePlacement]) -> [RemotePlacement] {
        on(locale, shots)
    }

    /// The copy was made and never published, so App Store Connect holds no
    /// `es-ES` set.
    @Test func makesTheCopyAppStoreConnectDoesNotHold() throws {
        try makeSpanishProject()
        let project = try fixture.load()
        let mexican = try remoteShots(locale: "es-MX")

        let outcome = try VersionSeed.seed(
            version: "2.0", from: listing(placements: spanishSet("es-MX", holding: mexican)), in: project
        )
        let files = try ContentStore.load(version: "2.0", in: project)
            .screenshots(locale: "es-ES", deviceClassID: DeviceClass.iPhone69.id)

        #expect(outcome.copied.map(\.locale) == ["es-MX"])
        #expect(outcome.fromSibling.map(\.locale) == ["es-ES"])
        #expect(outcome.fromSibling.map(\.from) == ["es-MX"])
        #expect(try isUnchanged(files, mexican))
        #expect(files.allSatisfy { $0.fileName.contains("es_ES") })
    }

    /// App Store Connect still holds the older `es-ES` pictures. The setting
    /// wins, and the report names the set once.
    @Test func namesASetOnceWhenTheCopyReplacesWhatTheStoreHolds() throws {
        try makeSpanishProject()
        let project = try fixture.load()
        let sets = try ["es-ES", "es-MX"].flatMap { try spanishSet($0, holding: remoteShots(locale: $0)) }

        let outcome = try VersionSeed.seed(version: "2.0", from: listing(placements: sets), in: project)
        let report = PushOutcomeText.describe(outcome, versionsPath: "versions")

        #expect(outcome.copied.map(\.locale) == ["es-MX"])
        #expect(outcome.fromSibling.map(\.locale) == ["es-ES"])
        #expect(report.contains("es-ES, iPhone 6.9 inch, from es-MX"))
    }

    @Test func refusesAVersionThatAlreadyHasAFolder() throws {
        #expect(throws: ContentWriteError.self) {
            try VersionSeed.seed(version: fixture.version, from: listing(placements: []), in: fixture.load())
        }
    }
}
