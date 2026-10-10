import Foundation
import Testing
@testable import ASCKitProject

/// A header or search results image waits in the same inbox as a screenshot,
/// and its name says the role and the language with no device class.
final class InboxCreativeTests {
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
    }

    deinit {
        fixture.remove()
    }

    @discardableResult
    func putInInbox(named fileName: String, width: Int, height: Int, hasAlpha: Bool = false) throws -> URL {
        let folder = try fixture.load().rootURL.appending(path: ProjectScaffold.inboxName)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: fileName)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try PNGWriter.write(to: url, width: width, height: height, hasAlpha: hasAlpha, seed: fileName)
        return url
    }

    func empty(_ trashed: [URL]) {
        for url in trashed {
            try? FileManager.default.removeItem(at: url)
        }
    }

    func creativeFolder(_ locale: String) throws -> [String] {
        let folder = try fixture.load().creativeURL(.version("1.0"), locale: locale)
        return try FileManager.default.contentsOfDirectory(atPath: folder.path)
            .filter { $0.hasPrefix(".") == false }
            .sorted()
    }

    // MARK: - Reading the names

    @Test func readsAHeaderAndSearchResultsByTheirNames() throws {
        try putInInbox(named: "header-en_US.png", width: 3840, height: 1646)
        try putInInbox(named: "search-results-en_US.png", width: 3840, height: 2560)

        let plan = try Inbox.plan(in: fixture.load())
        #expect(plan.refusals.isEmpty)
        #expect(plan.arrivals.isEmpty)
        #expect(plan.hasArrivals)
        #expect(Set(plan.creative.map(\.role)) == [.header, .searchResults])
        #expect(plan.creative.allSatisfy { $0.locale == "en-US" })
    }

    @Test(arguments: [(3840, 1646), (5244, 2950)])
    func takesEitherHeaderSize(width: Int, height: Int) throws {
        try putInInbox(named: "header-de_DE.png", width: width, height: height)

        let plan = try Inbox.plan(in: fixture.load())
        #expect(plan.refusals.isEmpty)
        #expect(plan.creative.map(\.locale) == ["de-DE"])
    }

    @Test func takesSearchResultsInsideTheRange() throws {
        try putInInbox(named: "search-results-en_US.png", width: 1920, height: 1280)

        let plan = try Inbox.plan(in: fixture.load())
        #expect(plan.refusals.isEmpty)
        #expect(plan.creative.map(\.role) == [.searchResults])
    }

    /// A word or a number before the role says nothing.
    @Test func dropsWhatComesBeforeTheRole() throws {
        try putInInbox(named: "01-moondane-header-en_US.png", width: 3840, height: 1646)

        let plan = try Inbox.plan(in: fixture.load())
        #expect(plan.creative.map(\.role) == [.header])
    }

    /// A name with a device class is a screenshot, whatever it shows.
    @Test func readsANameWithADeviceClassAsAScreenshot() throws {
        try putInInbox(named: "03-header-iPhone-6.9-en_US.png", width: 1290, height: 2796)

        let plan = try Inbox.plan(in: fixture.load())
        #expect(plan.creative.isEmpty)
        #expect(plan.arrivals.map(\.imageName) == ["header"])
    }

    /// The refusal names the pattern of a header, because a header has no
    /// device class to add.
    @Test func refusesAHeaderWithNoLanguageWithTheHeaderPattern() throws {
        try putInInbox(named: "header.png", width: 3840, height: 1646)

        let plan = try Inbox.plan(in: fixture.load())
        #expect(plan.creative.isEmpty)
        #expect(plan.hasInvalidNames)
        #expect(plan.refusals[0].reason.contains(ScreenshotNaming.creativeExample))
        #expect(plan.refusals[0].reason.contains(ScreenshotNaming.example) == false)
    }

    /// A design tool exports one folder per language, with one file name in
    /// each. The folder says the language.
    @Test(arguments: ["de-DE", "de_DE", "de", "export/de-DE"])
    func readsTheLanguageOfTheFolder(folder: String) throws {
        try putInInbox(named: "\(folder)/header.png", width: 3840, height: 1646)
        try putInInbox(named: "en-US/header.png", width: 3840, height: 1646)

        let plan = try Inbox.plan(in: fixture.load())
        #expect(plan.refusals.isEmpty)
        #expect(Set(plan.creative.map(\.locale)) == ["de-DE", "en-US"])
    }

    @Test func readsTheLanguageOfTheFolderForAScreenshot() throws {
        try putInInbox(named: "de-DE/01-overview-iPhone-6.9.png", width: 1290, height: 2796)

        let plan = try Inbox.plan(in: fixture.load())
        #expect(plan.refusals.isEmpty)
        #expect(plan.arrivals.map(\.locale) == ["de-DE"])
    }

    @Test func takesTheLanguageOfTheNameOverTheFolder() throws {
        try putInInbox(named: "de-DE/header-en_US.png", width: 3840, height: 1646)

        let plan = try Inbox.plan(in: fixture.load())
        #expect(plan.creative.map(\.locale) == ["en-US"])
    }

    @Test func refusesALanguageThisProjectDoesNotShip() throws {
        try putInInbox(named: "header-ja.png", width: 3840, height: 1646)

        let plan = try Inbox.plan(in: fixture.load())
        #expect(plan.creative.isEmpty)
        #expect(plan.refusals[0].reason.contains("does not ship"))
    }

    @Test func refusesTheWrongSizeAndSaysTheSizesItTakes() throws {
        try putInInbox(named: "header-en_US.png", width: 1290, height: 2796)

        let plan = try Inbox.plan(in: fixture.load())
        #expect(plan.creative.isEmpty)
        #expect(plan.refusals[0].reason.contains("1290x2796"))
        #expect(plan.refusals[0].reason.contains("3840x1646"))
    }

    @Test func refusesAnAlphaChannelAndOffersToClearIt() throws {
        try putInInbox(named: "header-en_US.png", width: 3840, height: 1646, hasAlpha: true)

        let plan = try Inbox.plan(in: fixture.load())
        #expect(plan.creative.isEmpty)
        #expect(plan.refusals[0].hasClearableAlpha)
        #expect(AlphaRemoval.clearable(in: plan).map(\.fileName) == ["header-en_US.png"])
    }

    @Test func refusesASecondFileForOneRole() throws {
        try putInInbox(named: "header-en_US.png", width: 3840, height: 1646)
        try putInInbox(named: "header-en_US.jpg", width: 3840, height: 1646)

        let plan = try Inbox.plan(in: fixture.load())
        #expect(plan.creative.count == 1)
        #expect(plan.refusals.count == 1)
        #expect(plan.refusals[0].reason.contains("Keep one"))
    }

    // MARK: - Filing it

    @Test func filesTheArtIntoTheCreativeFolderOfTheVersion() throws {
        let waiting = try putInInbox(named: "header-de_DE.png", width: 3840, height: 1646)
        try putInInbox(named: "search-results-de_DE.png", width: 3840, height: 2560)

        let project = try fixture.load()
        let outcome = try Inbox.file(Inbox.plan(in: project), version: "1.0", listing: nil, in: project)
        defer { empty(outcome.trashed) }

        #expect(outcome.filed == 0)
        #expect(outcome.creative.count == 2)
        #expect(try creativeFolder("de-DE") == ["header.png", "search-results.png"])
        #expect(FileManager.default.fileExists(atPath: waiting.path) == false)
        #expect(try Inbox.waiting(in: project).isEmpty)
    }

    @Test func replacesTheArtThatRoleHas() throws {
        let project = try fixture.load()
        let folder = project.creativeURL(.version("1.0"), locale: "en-US")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try PNGWriter.write(to: folder.appending(path: "header.jpg"), width: 3840, height: 1646, hasAlpha: false, seed: "old")
        try putInInbox(named: "header-en_US.png", width: 3840, height: 1646)

        let outcome = try Inbox.file(Inbox.plan(in: project), version: "1.0", listing: nil, in: project)
        defer { empty(outcome.trashed) }

        #expect(try creativeFolder("en-US") == ["header.png"])
    }

    @Test func filesScreenshotsAndArtInOneBatch() throws {
        try putInInbox(named: "01-hero-iPhone-6.9-en_US.png", width: 1290, height: 2796)
        try putInInbox(named: "header-en_US.png", width: 3840, height: 1646)

        let project = try fixture.load()
        let outcome = try Inbox.file(Inbox.plan(in: project), version: "1.0", listing: nil, in: project)
        defer { empty(outcome.trashed) }

        #expect(outcome.filed == 1)
        #expect(outcome.creative.map(\.role) == [.header])
        #expect(try creativeFolder("en-US") == ["header.png"])
    }
}
