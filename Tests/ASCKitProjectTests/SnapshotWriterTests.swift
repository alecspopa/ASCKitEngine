import ASCKitAPI
import Foundation
import Testing
@testable import ASCKitProject

final class SnapshotWriterTests {
    let fixture: FixtureProject

    init() throws {
        fixture = try FixtureProject()
        try fixture.writeConfig(ProjectConfig(
            bundleID: "com.example.Demo",
            keyID: "ABC123",
            issuerID: "issuer",
            sourceLocale: "en-US",
            locales: ["en-US", "de-DE"]
        ))
    }

    deinit {
        fixture.remove()
    }

    func makeListing(
        english: [String: String] = [
            "name": "Demo", "subtitle": "Shared pantry list",
            "description": "Know what you have.", "keywords": "household,restock"
        ],
        german: [String: String] = ["name": "Demo", "subtitle": "Geteilte Vorratsliste"]
    ) -> RemoteListing {
        func split(_ values: [String: String]) -> (info: [String: String], version: [String: String]) {
            var info: [String: String] = [:]
            var version: [String: String] = [:]
            for (key, value) in values {
                if key == "name" || key == "subtitle" || key == "privacyPolicyUrl" {
                    info[key] = value
                } else {
                    version[key] = value
                }
            }
            return (info, version)
        }

        let englishParts = split(english)
        let germanParts = split(german)

        return RemoteListing(
            appID: "app1",
            appName: "Demo",
            bundleID: "com.example.Demo",
            appInfoID: "info1",
            appInfoState: .prepareForSubmission,
            versionID: "v1",
            versionString: "1.0",
            versionState: .prepareForSubmission,
            appInfoLocalizations: [
                "en-US": RemoteLocalization(id: "i-en", locale: "en-US", values: englishParts.info),
                "de-DE": RemoteLocalization(id: "i-de", locale: "de-DE", values: germanParts.info)
            ],
            versionLocalizations: [
                "en-US": RemoteLocalization(id: "v-en", locale: "en-US", values: englishParts.version),
                "de-DE": RemoteLocalization(id: "v-de", locale: "de-DE", values: germanParts.version)
            ],
            screenshotSets: []
        )
    }

    // MARK: - Building one language

    /// Name and subtitle come from the app information, the rest from the
    /// version, and a app information file holds both together.
    @Test func joinsBothResourcesIntoOneCopyFile() {
        let copy = SnapshotWriter.makeInformation(locale: "en-US", listing: makeListing())

        #expect(copy.fields.name == "Demo")
        #expect(copy.fields.subtitle == "Shared pantry list")
        #expect(copy.fields.description == "Know what you have.")
        #expect(copy.fields.keywords == "household,restock")
    }

    /// An empty string blanks the field on the next push. A missing field
    /// leaves it alone, which is what an empty remote value means.
    @Test func leavesOutAFieldThatIsEmptyOnAppStoreConnect() {
        let copy = SnapshotWriter.makeInformation(
            locale: "en-US",
            listing: makeListing(english: ["name": "Demo", "promotionalText": ""])
        )
        #expect(copy.fields.promotionalText == nil)
        #expect(copy.fields.presentFields.contains(.promotionalText) == false)
    }

    /// What is live has been through review, so it is not a draft and not
    /// something a machine wrote unread.
    @Test func marksWhatIsLiveAsApproved() {
        #expect(SnapshotWriter.makeInformation(locale: "en-US", listing: makeListing()).status == .approved)
    }

    // MARK: - Writing

    @Test func writesOneFilePerLanguage() throws {
        let project = try fixture.load()
        let outcome = try SnapshotWriter.write(listing: makeListing(), to: project, version: "1.0")

        #expect(outcome.written.sorted() == ["de-DE", "en-US"])
        #expect(outcome.skipped.isEmpty)

        let content = try ContentStore.load(version: "1.0", in: project)
        #expect(content.appInformation["en-US"]?.fields.subtitle == "Shared pantry list")
        #expect(content.appInformation["de-DE"]?.fields.subtitle == "Geteilte Vorratsliste")
    }

    /// A pull that silently replaced local work would be the worst thing this
    /// tool could do.
    @Test func neverOverwritesLocalWorkByDefault() throws {
        let project = try fixture.load()
        try fixture.writeCopy(AppInformation(
            locale: "en-US",
            status: .approved,
            fields: AppInformation.Fields(subtitle: "Something I wrote myself")
        ))

        let outcome = try SnapshotWriter.write(listing: makeListing(), to: project, version: "1.0")

        #expect(outcome.skipped == ["en-US"])
        #expect(outcome.written == ["de-DE"])

        let content = try ContentStore.load(version: "1.0", in: project)
        #expect(content.appInformation["en-US"]?.fields.subtitle == "Something I wrote myself")
    }

    @Test func overwritesWhenExplicitlyAskedTo() throws {
        let project = try fixture.load()
        try fixture.writeCopy(AppInformation(
            locale: "en-US",
            status: .approved,
            fields: AppInformation.Fields(subtitle: "Something I wrote myself")
        ))

        let outcome = try SnapshotWriter.write(
            listing: makeListing(),
            to: project,
            version: "1.0",
            overwrite: true
        )

        #expect(outcome.written.sorted() == ["de-DE", "en-US"])
        let content = try ContentStore.load(version: "1.0", in: project)
        #expect(content.appInformation["en-US"]?.fields.subtitle == "Shared pantry list")
    }

    /// A translation written from a live listing matches that listing, so
    /// recording the digest saves it being reported as stale straight away.
    @Test func recordsWhichSourceEachTranslationMatches() throws {
        let project = try fixture.load()
        try SnapshotWriter.write(listing: makeListing(), to: project, version: "1.0")

        let content = try ContentStore.load(version: "1.0", in: project)
        let english = try #require(content.appInformation["en-US"])
        let german = try #require(content.appInformation["de-DE"])

        #expect(english.fields.name?.isEmpty == false)
        #expect(german.fields.name?.isEmpty == false)
    }

    /// The whole point: a pull of a real listing should leave a project that
    /// checks clean.
    @Test func leavesAProjectTheCheckerIsHappyWith() throws {
        try fixture.writeConfig(ProjectConfig(
            bundleID: "com.example.Demo",
            keyID: "ABC123",
            issuerID: "issuer",
            locales: ["en-US", "de-DE"],
            deviceClasses: []
        ))
        let project = try fixture.load()
        try SnapshotWriter.write(
            listing: makeListing(
                english: [
                    "name": "Demo", "subtitle": "Shared pantry list",
                    "description": "Know what you have.", "keywords": "household,restock",
                    "whatsNew": "First release.",
                    "supportUrl": "https://example.com/support",
                    "privacyPolicyUrl": "https://example.com/privacy"
                ],
                german: [
                    "name": "Demo", "subtitle": "Geteilte Vorratsliste",
                    "description": "Wissen, was da ist.", "keywords": "haushalt",
                    "whatsNew": "Erste Fassung.",
                    "supportUrl": "https://example.com/support"
                ]
            ),
            to: project,
            version: "1.0"
        )

        let result = try Checker.check(project: fixture.load(), version: "1.0")
        #expect(result.errors.isEmpty, "unexpected: \(result.errors.map(\.message.english))")
    }

    // MARK: - Filling what is empty here

    @Test func fillsAFieldThatSaysNothingYet() {
        let filled = SnapshotWriter.fill(
            AppInformation(locale: "en-US", fields: AppInformation.Fields(name: "Demo")),
            from: makeListing()
        )

        #expect(filled.information.fields.subtitle == "Shared pantry list")
        #expect(filled.information.fields.description == "Know what you have.")
        #expect(filled.fields.contains(.subtitle))
    }

    @Test func leavesWordsSomebodyWroteAsTheyAre() {
        let filled = SnapshotWriter.fill(
            AppInformation(
                locale: "en-US",
                fields: AppInformation.Fields(subtitle: "Something I wrote myself")
            ),
            from: makeListing()
        )

        #expect(filled.information.fields.subtitle == "Something I wrote myself")
        #expect(filled.fields.contains(.subtitle) == false)
    }

    /// A field holding a space reads as empty on screen and pushes as empty to
    /// the store, so it is empty here too.
    @Test func countsAFieldOfSpacesAsEmpty() {
        let filled = SnapshotWriter.fill(
            AppInformation(locale: "en-US", fields: AppInformation.Fields(subtitle: "  ")),
            from: makeListing()
        )

        #expect(filled.information.fields.subtitle == "Shared pantry list")
        #expect(filled.fields.contains(.subtitle))
    }

    /// A draft that gained one field is still a draft. Nothing becomes
    /// publishable because a field arrived from the store.
    @Test func keepsTheStatusTheFileHolds() {
        let filled = SnapshotWriter.fill(
            AppInformation(locale: "en-US", status: .draft),
            from: makeListing()
        )

        #expect(filled.information.status == .draft)
    }

    @Test func fillsNothingWhenAppStoreConnectHoldsNothingForTheLanguage() {
        let filled = SnapshotWriter.fill(
            AppInformation(locale: "fr-FR", fields: AppInformation.Fields(name: "Demo")),
            from: makeListing()
        )

        #expect(filled.fields.isEmpty)
        #expect(filled.information.fields.subtitle == nil)
    }

    @Test func writesEveryLanguageThatGainedSomething() throws {
        let project = try fixture.load()
        try fixture.writeCopy(AppInformation(
            locale: "en-US",
            status: .approved,
            fields: AppInformation.Fields(name: "Demo", subtitle: "Something I wrote myself")
        ))
        try fixture.writeCopy(AppInformation(locale: "de-DE", status: .draft))

        let content = try ContentStore.load(version: "1.0", in: project)
        let outcome = try SnapshotWriter.fill(
            content.appInformation,
            from: makeListing(),
            version: "1.0",
            in: project
        )

        #expect(outcome.locales == ["de-DE", "en-US"])
        #expect(outcome.filled["de-DE"]?.contains(.subtitle) == true)

        let written = try ContentStore.load(version: "1.0", in: project)
        #expect(written.appInformation["en-US"]?.fields.subtitle == "Something I wrote myself")
        #expect(written.appInformation["en-US"]?.fields.description == "Know what you have.")
        #expect(written.appInformation["de-DE"]?.fields.subtitle == "Geteilte Vorratsliste")
        #expect(written.appInformation["de-DE"]?.status == .draft)
    }

    /// A file that gained nothing is not written at all, so a read leaves the
    /// git history alone.
    @Test func writesNothingWhenEveryFieldAlreadySaysSomething() throws {
        let project = try fixture.load()
        try fixture.writeCopy(AppInformation(
            locale: "en-US",
            status: .approved,
            fields: AppInformation.Fields(name: "Mine", subtitle: "Mine too")
        ))

        let content = try ContentStore.load(version: "1.0", in: project)
        let outcome = try SnapshotWriter.fill(
            content.appInformation,
            from: makeListing(english: ["name": "Demo", "subtitle": "Shared pantry list"]),
            version: "1.0",
            in: project
        )

        #expect(outcome.isEmpty)
        let url = project.informationURL(version: "1.0", locale: "en-US")
        let written = try JSONDecoder().decode(AppInformation.self, from: Data(contentsOf: url))
        #expect(written.fields.name == "Mine")
    }

    /// Only the files that are there. Making one for a language App Store
    /// Connect holds and this project does not is what locale adoption is for,
    /// and it asks first.
    @Test func makesNoFileForALanguageThatHasNone() throws {
        let project = try fixture.load()
        try fixture.writeCopy(AppInformation(locale: "en-US"))

        let content = try ContentStore.load(version: "1.0", in: project)
        try SnapshotWriter.fill(
            content.appInformation,
            from: makeListing(),
            version: "1.0",
            in: project
        )

        let german = project.informationURL(version: "1.0", locale: "de-DE")
        #expect(FileManager.default.fileExists(atPath: german.path) == false)
    }

    // MARK: - Adopting the locale list

    /// App Store Connect is the authoritative answer to which codes it accepts.
    @Test func setsTheLocaleListToWhatAppStoreConnectHolds() throws {
        try fixture.writeConfig(ProjectConfig(
            bundleID: "com.example.Demo", keyID: "ABC123", issuerID: "issuer",
            locales: ["en-US", "ja-JP"]
        ))
        let updated = try SnapshotWriter.updateLocales(in: fixture.load(), from: makeListing())

        #expect(updated.locales == ["de-DE", "en-US"])
        #expect(try fixture.load().config.locales == ["de-DE", "en-US"])
    }

    @Test func keepsEverythingElseInTheConfiguration() throws {
        let before = try fixture.load().config
        _ = try SnapshotWriter.updateLocales(in: fixture.load(), from: makeListing())
        let after = try fixture.load().config

        #expect(after.bundleID == before.bundleID)
        #expect(after.keyID == before.keyID)
        #expect(after.issuerID == before.issuerID)
        #expect(after.sourceLocale == before.sourceLocale)
        #expect(after.deviceClasses == before.deviceClasses)
    }
}
