import ASCKitAPI
import Foundation
import Testing
@testable import ASCKitProject

/// An app usually ships in more languages than a project starts with. Until
/// those languages are in files, nothing here can show them, so the whole point
/// is noticing them and taking them in without standing on what is already
/// there.
final class LocaleAdoptionTests {
    let fixture: FixtureProject

    init() throws {
        fixture = try FixtureProject()
        try fixture.writeConfig(ProjectConfig(
            bundleID: "com.example.Demo",
            keyID: "ABC123",
            issuerID: "issuer",
            sourceLocale: "en-US",
            locales: ["en-US"],
            deviceClasses: [DeviceClass.iPhone69.id]
        ))
        try fixture.writeCopy(AppInformation(locale: "en-US", status: .approved))
    }

    deinit {
        fixture.remove()
    }

    func makeListing(locales: [String] = ["en-US", "de-DE", "fr-FR"]) -> RemoteListing {
        var info: [String: RemoteLocalization] = [:]
        var version: [String: RemoteLocalization] = [:]
        for locale in locales {
            info[locale] = RemoteLocalization(
                id: "i-\(locale)",
                locale: locale,
                values: ["name": "Demo", "subtitle": "Subtitle for \(locale)"]
            )
            version[locale] = RemoteLocalization(
                id: "v-\(locale)",
                locale: locale,
                values: ["description": "Description for \(locale)"]
            )
        }

        return RemoteListing(
            appID: "app1",
            appName: "Demo",
            bundleID: "com.example.Demo",
            appInfoID: "info1",
            appInfoState: .prepareForSubmission,
            versionID: "v1",
            versionString: fixture.version,
            versionState: .prepareForSubmission,
            appInfoLocalizations: info,
            versionLocalizations: version,
            screenshotSets: []
        )
    }

    // MARK: - Noticing

    @Test func namesTheLanguagesOnlyAppStoreConnectHas() throws {
        let config = try fixture.load().config
        let drift = LocaleDrift.compare(listing: makeListing(), config: config)

        #expect(drift.missingHere == ["de-DE", "fr-FR"])
        #expect(drift.missingThere.isEmpty)
        #expect(drift.agrees == false)
    }

    /// A language in the configuration that the store has never seen is news
    /// rather than a fault: a push creates it.
    @Test func namesTheLanguagesOnlyTheProjectHas() throws {
        let drift = try LocaleDrift.compare(
            listing: makeListing(locales: ["en-US"]),
            config: config(locales: ["en-US", "ro-RO"])
        )

        #expect(drift.missingHere.isEmpty)
        #expect(drift.missingThere == ["ro-RO"])
    }

    @Test func agreesWhenBothListsMatch() throws {
        let drift = try LocaleDrift.compare(
            listing: makeListing(locales: ["en-US"]),
            config: fixture.load().config
        )
        #expect(drift.agrees)
    }

    // MARK: - What can be taken in

    @Test func plansTheLanguagesAppStoreConnectHas() throws {
        let plan = try LocaleAdoption.plan(listing: makeListing(), project: fixture.load()).get()

        #expect(plan.locales == ["de-DE", "fr-FR"])
        #expect(plan.version == fixture.version)
    }

    /// The files would go into the newest folder on disk, which is a different
    /// version. Both front ends refuse this state, in these words.
    @Test func refusesWhenTheStoreIsOnAVersionWithNoFolder() throws {
        let config = try fixture.load().config
        let plan = LocaleAdoption.plan(
            locales: LocaleDrift.compare(listing: makeListing(), config: config),
            versions: .missingFolder(version: "2.0", newest: fixture.version),
            config: config
        )

        #expect(plan == .failure(.noFolderForVersion("2.0", versionsPath: "versions")))
    }

    @Test func refusesWhenNothingHasBeenReadYet() throws {
        let config = try fixture.load().config
        #expect(LocaleAdoption.plan(locales: nil, versions: nil, config: config) == .failure(.nothingReadYet))
    }

    @Test func refusesWhenEveryLanguageIsAlreadyHere() throws {
        let plan = try LocaleAdoption.plan(
            listing: makeListing(locales: ["en-US"]),
            project: fixture.load()
        )
        #expect(plan == .failure(.everythingIsAlreadyHere))
    }

    // MARK: - Taking them in

    @Test func addsTheLanguagesToTheLocaleList() throws {
        let adoption = try LocaleAdoption.adopt(listing: makeListing(), in: fixture.load())

        #expect(adoption.added == ["de-DE", "fr-FR"])
        #expect(try fixture.load().config.locales == ["en-US", "de-DE", "fr-FR"])
    }

    /// The source language stays first, because the order of the list is the
    /// order of the sidebar.
    @Test func keepsTheOrderOfTheLanguagesAlreadyListed() throws {
        try fixture.writeConfig(config(locales: ["en-US", "ro-RO"]))
        try LocaleAdoption.adopt(listing: makeListing(locales: ["en-US", "de-DE"]), in: fixture.load())

        #expect(try fixture.load().config.locales == ["en-US", "ro-RO", "de-DE"])
    }

    @Test func writesAnAppInformationFilePerLanguage() throws {
        let adoption = try LocaleAdoption.adopt(
            listing: makeListing(locales: ["en-US", "de-DE"]),
            in: fixture.load()
        )

        #expect(adoption.written == ["de-DE"])

        let content = try fixture.content()
        #expect(content.appInformation["de-DE"]?.fields.subtitle == "Subtitle for de-DE")
        #expect(content.appInformation["de-DE"]?.fields.description == "Description for de-DE")
    }

    @Test func makesTheFoldersTheScreenshotsGoIn() throws {
        try LocaleAdoption.adopt(listing: makeListing(locales: ["en-US", "de-DE"]), in: fixture.load())

        let folder = fixture.screenshotsDirectory(locale: "de-DE", deviceClassID: DeviceClass.iPhone69.id)
        #expect(FileManager.default.fileExists(atPath: folder.path))
    }

    /// The file on disk may be a translation somebody is still working on.
    @Test func leavesAnAppInformationFileThatIsAlreadyThere() throws {
        try fixture.writeCopy(AppInformation(
            locale: "de-DE",
            status: .draft,
            fields: AppInformation.Fields(subtitle: "Halb fertig")
        ))

        let adoption = try LocaleAdoption.adopt(
            listing: makeListing(locales: ["en-US", "de-DE"]),
            in: fixture.load()
        )

        #expect(adoption.written.isEmpty)
        #expect(try fixture.content().appInformation["de-DE"]?.fields.subtitle == "Halb fertig")
    }

    /// Adding what is already there writes nothing, so pressing the button
    /// twice cannot change the project.
    @Test func leavesALanguageThatIsAlreadyListed() throws {
        let adoption = try LocaleAdoption.adopt(
            LocaleAdoption.Plan(locales: ["en-US"], version: fixture.version),
            listing: makeListing(),
            in: fixture.load()
        )

        #expect(adoption.added.isEmpty)
        #expect(adoption.written.isEmpty)
        #expect(adoption.left == ["en-US"])
        #expect(try fixture.load().config.locales == ["en-US"])
    }

    /// The validator wants a file for every name in the locale list, so a
    /// language taken in has to arrive with one or the project reads as broken.
    @Test func leavesTheProjectWithNoNewProblems() throws {
        try LocaleAdoption.adopt(listing: makeListing(), in: fixture.load())

        let layout = try fixture.problems().filter { $0.area == .layout }
        #expect(layout.isEmpty)
    }

    private func config(locales: [String]) throws -> ProjectConfig {
        var config = try fixture.load().config
        config.locales = locales
        return config
    }
}
