import ASCKitAPI
import Foundation
import Testing
@testable import ASCKitProject

/// An app is often built in more languages than its store page is written in.
/// Ignoring a language keeps it in the list, so the Xcode check stops asking
/// for a listing to match, and takes it out of everything that writes or
/// checks.
final class IgnoredLocalesTests {
    let fixture: FixtureProject

    init() throws {
        fixture = try FixtureProject()
        try fixture.writeConfig(config())
    }

    deinit {
        fixture.remove()
    }

    func config(
        locales: [String] = ["en-US", "de-DE", "ro"],
        ignoredLocales: [String] = []
    ) -> ProjectConfig {
        ProjectConfig(
            bundleID: "com.example.Demo",
            keyID: "ABC123",
            issuerID: "issuer",
            sourceLocale: "en-US",
            locales: locales,
            ignoredLocales: ignoredLocales,
            deviceClasses: [DeviceClass.iPhone69.id]
        )
    }

    // MARK: - Writing the decision

    @Test func keepsAnIgnoredLanguageInTheLocaleList() throws {
        let written = try IgnoredLocales.set(true, locale: "ro", in: fixture.load())

        #expect(written.ignoredLocales == ["ro"])
        #expect(written.locales == ["en-US", "de-DE", "ro"])
        #expect(written.writtenLocales == ["en-US", "de-DE"])
    }

    @Test func readsTheDecisionBackFromTheFile() throws {
        try IgnoredLocales.set(true, locale: "ro", in: fixture.load())

        #expect(try fixture.load().config.isIgnored("ro"))
    }

    @Test func takesTheDecisionBack() throws {
        try IgnoredLocales.set(true, locale: "ro", in: fixture.load())
        let written = try IgnoredLocales.set(false, locale: "ro", in: fixture.load())

        #expect(written.ignoredLocales.isEmpty)
        #expect(written.writtenLocales == ["en-US", "de-DE", "ro"])
    }

    @Test func ignoringTwiceNamesItOnce() throws {
        try IgnoredLocales.set(true, locale: "ro", in: fixture.load())
        let written = try IgnoredLocales.set(true, locale: "ro", in: fixture.load())

        #expect(written.ignoredLocales == ["ro"])
    }

    /// Every other language is translated from the source language, so a
    /// listing with none has nothing to say.
    @Test func refusesTheSourceLanguage() throws {
        #expect(throws: IgnoredLocaleError.sourceLanguage("en-US")) {
            try IgnoredLocales.set(true, locale: "en-US", in: fixture.load())
        }
    }

    @Test func refusesALanguageTheProjectDoesNotList() throws {
        let project = try fixture.load()

        #expect(throws: IgnoredLocaleError.notListed("ja", listed: project.config.locales)) {
            try IgnoredLocales.set(true, locale: "ja", in: project)
        }
    }

    // MARK: - What goes to the Trash

    /// A folder holding words nothing reads is a folder somebody edits by
    /// mistake, so ignoring takes the language's files out of the project.
    @Test func movesTheLanguageTextToTheTrash() throws {
        try fixture.writeCopy(AppInformation(locale: "ro", status: .draft))
        let url = fixture.rootURL
            .appending(path: "versions").appending(path: fixture.version)
            .appending(path: Project.informationFolderName).appending(path: "ro.json")

        try IgnoredLocales.set(true, locale: "ro", in: fixture.load())

        #expect(FileManager.default.fileExists(atPath: url.path) == false)
    }

    @Test func movesTheLanguageScreenshotsToTheTrash() throws {
        let size = DeviceClass.iPhone69.acceptedSizes[0]
        try fixture.writeScreenshot(
            locale: "ro",
            deviceClassID: DeviceClass.iPhone69.id,
            named: "01.png",
            width: size.width,
            height: size.height
        )
        let url = fixture.rootURL
            .appending(path: "versions").appending(path: fixture.version)
            .appending(path: "screenshots").appending(path: "ro")

        try IgnoredLocales.set(true, locale: "ro", in: fixture.load())

        #expect(FileManager.default.fileExists(atPath: url.path) == false)
    }

    @Test func leavesEveryOtherLanguageWhereItIs() throws {
        try fixture.writeCopy(AppInformation(locale: "de-DE", status: .draft))
        let url = fixture.rootURL
            .appending(path: "versions").appending(path: fixture.version)
            .appending(path: Project.informationFolderName).appending(path: "de-DE.json")

        try IgnoredLocales.set(true, locale: "ro", in: fixture.load())

        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    /// Nothing here writes a file back. The words are on App Store Connect, and
    /// a pull is what brings them down.
    @Test func writesNoFileBackWhenTheIgnoreIsTakenBack() throws {
        try fixture.writeCopy(AppInformation(locale: "ro", status: .draft))
        try IgnoredLocales.set(true, locale: "ro", in: fixture.load())
        let url = fixture.rootURL
            .appending(path: "versions").appending(path: fixture.version)
            .appending(path: Project.informationFolderName).appending(path: "ro.json")

        try IgnoredLocales.set(false, locale: "ro", in: fixture.load())

        #expect(FileManager.default.fileExists(atPath: url.path) == false)
    }

    // MARK: - What stops happening

    /// The whole reason to ignore a language: no file is asked for, and the
    /// warning about the missing one goes away.
    @Test func asksForNoAppInformationFile() throws {
        try fixture.writeConfig(config(ignoredLocales: ["ro"]))
        try fixture.writeCopy(AppInformation(locale: "en-US", status: .approved))
        try fixture.writeCopy(AppInformation(locale: "de-DE", status: .approved))

        let project = try fixture.load()
        let problems = try Validator(config: project.config)
            .validate(ContentStore.load(version: "1.0", in: project))

        #expect(problems.contains { $0.locale == "ro" } == false)
    }

    @Test func writesNoAppInformationFileForIt() throws {
        try fixture.writeConfig(config(ignoredLocales: ["ro"]))
        try fixture.writeCopy(AppInformation(locale: "en-US", status: .approved))

        let written = try MissingLocaleFiles.write(in: fixture.load())

        #expect(written == ["de-DE"])
    }

    @Test func plansNothingForIt() throws {
        try fixture.writeConfig(config(ignoredLocales: ["ro"]))
        for locale in ["en-US", "de-DE", "ro"] {
            try fixture.writeCopy(AppInformation(
                locale: locale,
                status: .approved,
                fields: AppInformation.Fields(description: "Words in \(locale)")
            ))
        }

        let project = try fixture.load()
        let plan = try Planner.plan(
            local: ContentStore.load(version: "1.0", in: project),
            config: project.config,
            remote: listing(locales: ["en-US", "de-DE", "ro"])
        )

        #expect(plan.textChanges.contains { $0.locale == "ro" } == false)
        #expect(plan.missingLocales.contains("ro") == false)
        #expect(plan.skipped.contains { $0.locale == "ro" } == false)
    }

    /// The store has no page for an ignored language and never will, so it is
    /// not something the project and the store disagree about.
    @Test func isNotDriftAgainstAppStoreConnect() {
        let drift = LocaleDrift.compare(remote: ["en-US", "de-DE"], config: config(ignoredLocales: ["ro"]))

        #expect(drift.missingThere.isEmpty)
        #expect(drift.agrees)
    }

    /// The store cannot answer for a language it has no page for, so a rewrite
    /// of the list from the store leaves the ignored ones where they are.
    @Test func survivesARewriteOfTheListFromTheStore() throws {
        try fixture.writeConfig(config(ignoredLocales: ["ro"]))

        let written = try SnapshotWriter.updateLocales(
            in: fixture.load(),
            from: listing(locales: ["en-US", "de-DE"])
        )

        #expect(written.locales == ["de-DE", "en-US", "ro"])
        #expect(written.ignoredLocales == ["ro"])
    }

    // MARK: - Names that mean nothing

    @Test func reportsAnIgnoredLanguageThatIsNotListed() {
        let problems = Validator(config: config(locales: ["en-US"], ignoredLocales: ["ro"]))
            .validateConfiguration()

        #expect(problems.contains { $0.kind == .ignoredLocaleNotListed })
    }

    @Test func reportsAnIgnoredSourceLanguage() {
        let problems = Validator(config: config(ignoredLocales: ["en-US"])).validateConfiguration()

        #expect(problems.contains { $0.kind == .sourceLocaleIgnored })
    }

    // MARK: - Helpers

    func listing(locales: [String]) -> RemoteListing {
        var info: [String: RemoteLocalization] = [:]
        var version: [String: RemoteLocalization] = [:]
        for locale in locales {
            info[locale] = RemoteLocalization(id: "i-\(locale)", locale: locale, values: [:])
            version[locale] = RemoteLocalization(id: "v-\(locale)", locale: locale, values: [:])
        }

        return RemoteListing(
            appID: "app1",
            appName: "Demo",
            bundleID: "com.example.Demo",
            appInfoID: "info1",
            appInfoState: .prepareForSubmission,
            versionID: "v1",
            versionString: "1.0",
            versionState: .prepareForSubmission,
            appInfoLocalizations: info,
            versionLocalizations: version,
            screenshotSets: []
        )
    }
}
