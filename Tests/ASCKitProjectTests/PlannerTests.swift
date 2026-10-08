import ASCKitAPI
import Foundation
import Testing
@testable import ASCKitProject

final class PlannerTests {
    let fixture: FixtureProject

    init() throws {
        fixture = try FixtureProject()
    }

    deinit {
        fixture.remove()
    }

    // MARK: - Building the two sides

    func config(locales: [String] = ["en-US"], deviceClasses: [String] = []) -> ProjectConfig {
        ProjectConfig(
            bundleID: "com.example.Demo",
            keyID: "ABC123",
            issuerID: "issuer",
            sourceLocale: "en-US",
            locales: locales,
            deviceClasses: deviceClasses
        )
    }

    /// App Store Connect holds a localization for every language its store page
    /// is in, with an empty string in a field nobody has set. ASCKit writes into
    /// those and never makes one, so `locales` says which pages are there and
    /// `appInfo` and `version` say what is written in them.
    func listing(
        versionState: AppVersionState = .prepareForSubmission,
        appInfoState: AppInfoState = .prepareForSubmission,
        locales: [String] = ["en-US"],
        appInfo: [String: [String: String]] = [:],
        version: [String: [String: String]] = [:],
        screenshotSets: [RemoteScreenshotSet] = []
    ) -> RemoteListing {
        var appInfo = appInfo
        var version = version
        for locale in locales {
            appInfo[locale] = appInfo[locale] ?? [:]
            version[locale] = version[locale] ?? [:]
        }

        return RemoteListing(
            appID: "app1",
            appName: "Demo",
            bundleID: "com.example.Demo",
            appInfoID: appInfoState == .prepareForSubmission ? "info1" : nil,
            appInfoState: appInfoState,
            versionID: "v1",
            versionString: "1.0",
            versionState: versionState,
            appInfoLocalizations: appInfo.mapValues {
                RemoteLocalization(id: "i-\($0.hashValue)", locale: "", values: $0)
            },
            versionLocalizations: version.mapValues {
                RemoteLocalization(id: "v-\($0.hashValue)", locale: "", values: $0)
            },
            screenshotSets: screenshotSets
        )
    }

    func content(_ copies: [AppInformation]) throws -> VersionContent {
        try fixture.writeConfig(config())
        for copy in copies {
            try fixture.writeCopy(copy)
        }
        return try ContentStore.load(version: "1.0", in: fixture.load())
    }

    // MARK: - Text

    @Test func reportsAFieldTheListingDoesNotHaveYetAsAnAddition() throws {
        let local = try content([AppInformation(
            locale: "en-US", status: .approved,
            fields: AppInformation.Fields(subtitle: "Shared pantry list")
        )])

        let plan = Planner.plan(local: local, config: config(), remote: listing())
        let change = try #require(plan.textChanges.first)

        #expect(change.action == .add)
        #expect(change.field == .subtitle)
        #expect(change.oldValue == nil)
        #expect(change.newValue == "Shared pantry list")
    }

    @Test func reportsAFieldWithADifferentValueAsAChange() throws {
        let local = try content([AppInformation(
            locale: "en-US", status: .approved,
            fields: AppInformation.Fields(subtitle: "Shared pantry list")
        )])
        let remote = listing(appInfo: ["en-US": ["subtitle": "Something older"]])

        let change = try #require(Planner.plan(local: local, config: config(), remote: remote).textChanges.first)
        #expect(change.action == .change)
        #expect(change.oldValue == "Something older")
    }

    @Test func reportsNothingForAFieldThatAlreadyMatches() throws {
        let local = try content([AppInformation(
            locale: "en-US", status: .approved,
            fields: AppInformation.Fields(subtitle: "Shared pantry list")
        )])
        let remote = listing(appInfo: ["en-US": ["subtitle": "Shared pantry list"]])

        let plan = Planner.plan(local: local, config: config(), remote: remote)
        #expect(plan.textChanges.isEmpty)
        #expect(plan.isEmpty)
    }

    /// Apple returns an empty string for a field that was never set, which is
    /// an addition rather than a change from nothing to something.
    @Test func treatsAnEmptyRemoteValueAsNotSet() throws {
        let local = try content([AppInformation(
            locale: "en-US", status: .approved,
            fields: AppInformation.Fields(promotionalText: "New this week")
        )])
        let remote = listing(version: ["en-US": ["promotionalText": ""]])

        let change = try #require(Planner.plan(local: local, config: config(), remote: remote).textChanges.first)
        #expect(change.action == .add)
    }

    /// A field the project does not set is left alone on App Store Connect
    /// rather than blanked.
    @Test func leavesAloneAFieldTheProjectDoesNotSet() throws {
        let local = try content([AppInformation(
            locale: "en-US", status: .approved,
            fields: AppInformation.Fields(subtitle: "Shared pantry list")
        )])
        let remote = listing(version: ["en-US": ["description": "Something already there"]])

        let plan = Planner.plan(local: local, config: config(), remote: remote)
        #expect(plan.textChanges.contains { $0.field == .description } == false)
    }

    @Test func looksForNameAndSubtitleOnTheAppInformationOnly() throws {
        let local = try content([AppInformation(
            locale: "en-US", status: .approved,
            fields: AppInformation.Fields(name: "Demo", subtitle: "Shared pantry list")
        )])
        // The same values, but filed under the version, where they do not live.
        let remote = listing(version: ["en-US": ["name": "Demo", "subtitle": "Shared pantry list"]])

        let plan = Planner.plan(local: local, config: config(), remote: remote)
        #expect(plan.textChanges.count == 2, "both should read as missing, not as matching")
    }

    // MARK: - What gets left out

    @Test func leavesOutALanguageThatIsNotApproved() throws {
        let local = try content([
            AppInformation(locale: "en-US", status: .approved, fields: AppInformation.Fields(subtitle: "One")),
            AppInformation(locale: "de-DE", status: .needsHuman, fields: AppInformation.Fields(subtitle: "Zwei"))
        ])

        let plan = Planner.plan(local: local, config: config(locales: ["en-US", "de-DE"]), remote: listing())

        #expect(plan.textChanges.allSatisfy { $0.locale == "en-US" })
        #expect(plan.skipped.contains { $0.locale == "de-DE" && $0.reason.english == "marked needs_human" })
    }

    @Test func leavesOutALanguageWithNoCopyFile() throws {
        let local = try content([AppInformation(locale: "en-US", status: .approved)])
        let plan = Planner.plan(local: local, config: config(locales: ["en-US", "fr-FR"]), remote: listing())

        #expect(plan.skipped.contains { $0.locale == "fr-FR" && $0.reason.english == "no app information file" })
    }

    @Test func namesLanguagesAppStoreConnectHasNoPageFor() throws {
        let local = try content([
            AppInformation(locale: "en-US", status: .approved, fields: AppInformation.Fields(subtitle: "One")),
            AppInformation(locale: "de-DE", status: .approved, fields: AppInformation.Fields(subtitle: "Zwei"))
        ])
        let remote = listing(appInfo: ["en-US": ["subtitle": "One"]])

        let plan = Planner.plan(local: local, config: config(locales: ["en-US", "de-DE"]), remote: remote)
        #expect(plan.missingLocales == ["de-DE"])
    }

    /// ASCKit never makes a language on App Store Connect, so a language the
    /// store has no page for is named and left alone.
    @Test func writesNothingInALanguageAppStoreConnectHasNoPageFor() throws {
        let local = try content([
            AppInformation(locale: "en-US", status: .approved, fields: AppInformation.Fields(subtitle: "One")),
            AppInformation(locale: "de-DE", status: .approved, fields: AppInformation.Fields(subtitle: "Zwei"))
        ])
        let remote = listing(appInfo: ["en-US": ["subtitle": "One"]])

        let plan = Planner.plan(local: local, config: config(locales: ["en-US", "de-DE"]), remote: remote)
        #expect(plan.textChanges.allSatisfy { $0.locale == "en-US" })
    }

    // MARK: - States that refuse changes

    @Test func saysWhenTheVersionRefusesTextChanges() throws {
        let local = try content([AppInformation(
            locale: "en-US", status: .approved,
            fields: AppInformation.Fields(description: "Know what you have.")
        )])
        let remote = listing(versionState: .inReview, appInfoState: .readyForDistribution)

        let plan = Planner.plan(local: local, config: config(), remote: remote)
        #expect(plan.blocked.contains { $0.reason.english.contains("does not accept text changes") })
    }

    /// Once a version is live, the name and the subtitle are fixed until a new
    /// one is editable, even though other text can still change.
    @Test func saysWhenOnlyTheNameAndSubtitleAreFixed() throws {
        let local = try content([AppInformation(
            locale: "en-US", status: .approved,
            fields: AppInformation.Fields(name: "Demo", description: "Know what you have.")
        )])
        let remote = listing(versionState: .prepareForSubmission, appInfoState: .readyForDistribution)

        let plan = Planner.plan(local: local, config: config(), remote: remote)
        #expect(plan.blocked.count == 1)
        #expect(plan.blocked.first?.reason.english.contains("name and the subtitle") == true)
    }

    @Test func saysNothingIsBlockedWhenEverythingIsEditable() throws {
        let local = try content([AppInformation(
            locale: "en-US", status: .approved,
            fields: AppInformation.Fields(name: "Demo", description: "Know what you have.")
        )])
        #expect(Planner.plan(local: local, config: config(), remote: listing()).blocked.isEmpty)
    }
}
