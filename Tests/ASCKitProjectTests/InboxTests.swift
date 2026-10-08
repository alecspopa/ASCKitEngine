import Foundation
import Testing
@testable import ASCKitProject

/// The inbox is the one folder a person puts a file in by hand, so what it
/// says about that file has to be right before anything moves.
final class InboxTests {
    let fixture: FixtureProject

    init() throws {
        fixture = try FixtureProject()
        try fixture.writeConfig(ProjectConfig(
            bundleID: "com.example.Demo",
            keyID: "ABC123",
            issuerID: "issuer",
            sourceLocale: "en-US",
            locales: ["en-US", "de-DE"],
            deviceClasses: [DeviceClass.iPhone69.id, DeviceClass.iPad13.id]
        ))
    }

    deinit {
        fixture.remove()
    }

    @discardableResult
    func putInInbox(
        named fileName: String,
        in subfolder: String? = nil,
        width: Int = 1290,
        height: Int = 2796,
        hasAlpha: Bool = false
    ) throws -> URL {
        var folder = try fixture.load().rootURL.appending(path: ProjectScaffold.inboxName)
        if let subfolder { folder.append(path: subfolder) }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let url = folder.appending(path: fileName)
        try PNGWriter.write(to: url, width: width, height: height, hasAlpha: hasAlpha, seed: fileName)
        return url
    }

    /// The Trash is somebody's real Trash, so a test that fills it cleans up
    /// after itself.
    func empty(_ trashed: [URL]) {
        for url in trashed {
            try? FileManager.default.removeItem(at: url)
        }
    }

    func slot(locale: String = "en-US", deviceClassID: String = DeviceClass.iPhone69.id) throws -> [String] {
        let directory = fixture.screenshotsDirectory(locale: locale, deviceClassID: deviceClassID)
        return try FileManager.default
            .contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasPrefix(".") == false }
            .sorted { $0.compare($1, options: .numeric) == .orderedAscending }
    }

    // MARK: - Reading the folder

    @Test func readsWhatIsWaitingInNameOrder() throws {
        try putInInbox(named: "02-shared-iPhone-6.9-en_US.png")
        try putInInbox(named: "01-hero-iPhone-6.9-en_US.png")

        let waiting = try Inbox.waiting(in: fixture.load())
        #expect(waiting.map(\.fileName) == [
            "01-hero-iPhone-6.9-en_US.png", "02-shared-iPhone-6.9-en_US.png"
        ])
    }

    /// The folder holds its own `.gitignore`, and a person can drop anything
    /// else in a folder they can see.
    @Test func saysNothingAboutAFileThatIsNotAnImage() throws {
        try putInInbox(named: "01-hero-iPhone-6.9-en_US.png")

        let folder = try fixture.load().rootURL.appending(path: ProjectScaffold.inboxName)
        try Data("not an image".utf8).write(to: folder.appending(path: "notes.txt"))

        let waiting = try Inbox.waiting(in: fixture.load())
        #expect(waiting.map(\.fileName) == ["01-hero-iPhone-6.9-en_US.png"])
    }

    /// A design tool exports one folder per language, and a person drops the
    /// whole export in.
    @Test func readsTheSubfoldersInNameOrder() throws {
        try putInInbox(named: "02-shared-iPhone-6.9-de_DE.png", in: "v7/de-DE")
        try putInInbox(named: "01-hero-iPhone-6.9-en_US.png", in: "v7/en-US")
        try putInInbox(named: "01-hero-iPhone-6.9-de_DE.png", in: "v7/de-DE")

        let waiting = try Inbox.waiting(in: fixture.load())
        #expect(waiting.map(\.fileName) == [
            "01-hero-iPhone-6.9-de_DE.png",
            "01-hero-iPhone-6.9-en_US.png",
            "02-shared-iPhone-6.9-de_DE.png"
        ])
    }

    @Test func readsAnEmptyFolderAsNothingWaiting() throws {
        #expect(try Inbox.plan(in: fixture.load()).isEmpty)
    }

    // MARK: - Working out where it goes

    /// The name is the whole instruction, so a refusal has to say what to type
    /// rather than only that something is wrong.
    @Test func refusesAnImageWhoseNameSaysNoLanguage() throws {
        try putInInbox(named: "01-hero-iPhone-6.9.png")

        let plan = try Inbox.plan(in: fixture.load())
        #expect(plan.arrivals.isEmpty)
        #expect(plan.hasInvalidNames)
        #expect(plan.refusals[0].reason.contains("is not a language"))
        #expect(plan.refusals[0].reason.contains(ScreenshotNaming.example))
    }

    @Test func refusesALanguageThisProjectDoesNotShip() throws {
        try putInInbox(named: "01-hero-iPhone-6.9-ja.png")

        let plan = try Inbox.plan(in: fixture.load())
        #expect(plan.arrivals.isEmpty)
        #expect(plan.hasInvalidNames == false)
        #expect(plan.refusals[0].reason.contains("ja"))
        #expect(plan.refusals[0].reason.contains("de-DE"))
    }

    @Test func refusesAnImageWhoseNameSaysNoDevice() throws {
        try putInInbox(named: "01-hero-en_US.png")

        let plan = try Inbox.plan(in: fixture.load())
        #expect(plan.arrivals.isEmpty)
        #expect(plan.refusals[0].reason.contains("does not say which device"))
    }

    @Test func sendsEachImageWhereItsNameSaysItGoes() throws {
        try putInInbox(named: "01-hero-iPhone-6.9-de_DE.png")

        let plan = try Inbox.plan(in: fixture.load())
        #expect(plan.arrivals.count == 1)
        #expect(plan.arrivals[0].locale == "de-DE")
        #expect(plan.arrivals[0].deviceClass == .iPhone69)
        #expect(plan.arrivals[0].imageName == "hero")
    }

    @Test func splitsOneBatchAcrossTheDeviceClassesTheNamesName() throws {
        try putInInbox(named: "01-phone-iPhone-6.9-en_US.png", width: 1290, height: 2796)
        try putInInbox(named: "01-pad-iPad-13-en_US.png", width: 2064, height: 2752)

        let plan = try Inbox.plan(in: fixture.load())
        #expect(plan.refusals.isEmpty)
        #expect(plan.arrivals.count == 2)
        #expect(plan.arrivals.first { $0.imageName == "phone" }?.deviceClass == .iPhone69)
        #expect(plan.arrivals.first { $0.imageName == "pad" }?.deviceClass == .iPad13)
    }

    /// The name says one device class and the image is the size of another, so
    /// the reason has to be the size rather than the name.
    @Test func refusesAnImageTheDeviceClassInItsNameWouldNotTake() throws {
        try putInInbox(named: "01-small-iPhone-6.9-en_US.png", width: 800, height: 600)

        let plan = try Inbox.plan(in: fixture.load())
        #expect(plan.arrivals.isEmpty)
        #expect(plan.refusals.count == 1)
        #expect(plan.hasInvalidNames == false)
        #expect(plan.refusals[0].reason.contains("800x600"))
        #expect(plan.refusals[0].reason.contains("iPhone 6.9 inch"))
    }

    /// The size is right and the file is still refused, so the reason has to
    /// name the alpha channel rather than the size.
    @Test func saysTheAlphaChannelIsWhyWhenTheSizeIsRight() throws {
        try putInInbox(named: "01-clear-iPhone-6.9-en_US.png", hasAlpha: true)

        let plan = try Inbox.plan(in: fixture.load())
        #expect(plan.arrivals.isEmpty)
        #expect(plan.refusals[0].reason.contains("alpha channel"))
    }

    @Test func refusesADeviceClassThisProjectDoesNotList() throws {
        try putInInbox(named: "01-hero-iPhone-6.5-en_US.png", width: 1284, height: 2778)

        let plan = try Inbox.plan(in: fixture.load())
        #expect(plan.arrivals.isEmpty)
        #expect(plan.hasInvalidNames == false)
        #expect(plan.refusals[0].reason.contains("does not list"))
        #expect(plan.refusals[0].reason.contains("iphone-6.9"))
    }

    // MARK: - Filing it

    @Test func filesEveryImageIntoTheLanguageItsNameNamesAndNumbersTheSet() throws {
        try putInInbox(named: "01-hero-iPhone-6.9-de_DE.png")
        try putInInbox(named: "02-shared-iPhone-6.9-de_DE.png")

        let project = try fixture.load()
        let outcome = try Inbox.file(Inbox.plan(in: project), version: "1.0", in: project)
        defer { empty(outcome.trashed) }

        #expect(outcome.filed == 2)
        #expect(outcome.locales == ["de-DE"])
        #expect(try slot(locale: "de-DE") == [
            "01-hero-iPhone-6.9-de_DE.png",
            "02-shared-iPhone-6.9-de_DE.png"
        ])
    }

    @Test func filesAnImageFromASubfolder() throws {
        let waiting = try putInInbox(named: "01-hero-iPhone-6.9-de_DE.png", in: "v7/de-DE")

        let project = try fixture.load()
        let outcome = try Inbox.file(Inbox.plan(in: project), version: "1.0", in: project)
        defer { empty(outcome.trashed) }

        #expect(outcome.filed == 1)
        #expect(try slot(locale: "de-DE") == ["01-hero-iPhone-6.9-de_DE.png"])
        #expect(FileManager.default.fileExists(atPath: waiting.path) == false)
    }

    /// The Finder writes a `.DS_Store` into a folder a person opened, so a
    /// folder with only that in it is empty.
    @Test func removesTheSubfoldersFilingEmptied() throws {
        let waiting = try putInInbox(named: "01-hero-iPhone-6.9-de_DE.png", in: "v7/de-DE")
        try Data().write(to: waiting.deletingLastPathComponent().appending(path: ".DS_Store"))

        let project = try fixture.load()
        let outcome = try Inbox.file(Inbox.plan(in: project), version: "1.0", in: project)
        defer { empty(outcome.trashed) }

        let inbox = Inbox.url(in: project)
        #expect(FileManager.default.fileExists(atPath: inbox.appending(path: "v7").path) == false)
        #expect(FileManager.default.fileExists(atPath: inbox.path))
    }

    /// A refused image stays in its folder for a person to fix, and an empty
    /// folder that held no filed image is somebody else's.
    @Test func keepsASubfolderThatStillHoldsAFile() throws {
        try putInInbox(named: "01-hero-iPhone-6.9-de_DE.png", in: "v7/de-DE")
        try putInInbox(named: "01-hero-iPhone-6.9-ja.png", in: "v7/ja")

        let project = try fixture.load()
        let inbox = Inbox.url(in: project)
        let untouched = inbox.appending(path: "next")
        try FileManager.default.createDirectory(at: untouched, withIntermediateDirectories: true)

        let outcome = try Inbox.file(Inbox.plan(in: project), version: "1.0", in: project)
        defer { empty(outcome.trashed) }

        #expect(FileManager.default.fileExists(atPath: inbox.appending(path: "v7/de-DE").path) == false)
        #expect(FileManager.default.fileExists(atPath: inbox.appending(path: "v7/ja").path))
        #expect(FileManager.default.fileExists(atPath: untouched.path))
    }

    // MARK: - A language that copies the one the pictures went into

    /// Two Spanishes holding one older picture each, where `es-ES` is set to
    /// copy `es-MX`.
    func makeSpanishProject() throws {
        try fixture.writeConfig(ProjectConfig(
            bundleID: "com.example.Demo",
            keyID: "ABC123",
            issuerID: "issuer",
            sourceLocale: "en-US",
            locales: ["en-US", "de-DE", "es-ES", "es-MX"],
            deviceClasses: [DeviceClass.iPhone69.id],
            copiesScreenshotsFrom: ["es-ES": [DeviceClass.iPhone69.id: "es-MX"]]
        ))
        for locale in ["es-ES", "es-MX"] {
            try fixture.writeScreenshot(
                locale: locale, deviceClassID: DeviceClass.iPhone69.id,
                named: "01-hero.png", width: 1290, height: 2796, seed: "spanish/hero"
            )
            try fixture.setModified(
                locale: locale, deviceClassID: DeviceClass.iPhone69.id,
                to: Date(timeIntervalSince1970: 1_700_000_000)
            )
        }
    }

    @Test func givesTheNewPicturesToTheLanguageThatCopiesThisOne() throws {
        try makeSpanishProject()
        try putInInbox(named: "02-shared-iPhone-6.9-es_MX.png")

        let project = try fixture.load()
        let outcome = try Inbox.file(Inbox.plan(in: project), version: "1.0", in: project)
        defer { empty(outcome.trashed) }

        #expect(outcome.locales == ["es-MX"])
        #expect(outcome.copied.map(\.locale) == ["es-ES"])
        #expect(outcome.copied.map(\.from) == ["es-MX"])
        #expect(try slot(locale: "es-ES") == [
            "01-hero-iPhone-6.9-es_ES.png",
            "02-shared-iPhone-6.9-es_ES.png"
        ])
    }

    /// A newer `es-MX` picture is already there, put in with the Finder. German
    /// pictures arriving say nothing new about the Spanish sets, so filing them
    /// moves no Spanish file.
    @Test func leavesTheCopiesAloneWhenAnotherLanguageGetsPictures() throws {
        try makeSpanishProject()
        try fixture.writeScreenshot(
            locale: "es-MX", deviceClassID: DeviceClass.iPhone69.id,
            named: "02-shared.png", width: 1290, height: 2796
        )
        try putInInbox(named: "01-hero-iPhone-6.9-de_DE.png")

        let project = try fixture.load()
        let outcome = try Inbox.file(Inbox.plan(in: project), version: "1.0", in: project)
        defer { empty(outcome.trashed) }

        #expect(outcome.copied.isEmpty)
        #expect(try slot(locale: "es-ES") == ["01-hero.png"])
    }

    /// One batch, two languages. Every image carries its own destination, so
    /// nothing has to be dropped in one folder at a time.
    @Test func splitsOneBatchAcrossTheLanguagesTheNamesName() throws {
        try putInInbox(named: "01-hero-iPhone-6.9-en_US.png")
        try putInInbox(named: "01-hero-iPhone-6.9-de_DE.png")

        let project = try fixture.load()
        let outcome = try Inbox.file(Inbox.plan(in: project), version: "1.0", in: project)
        defer { empty(outcome.trashed) }

        #expect(outcome.filed == 2)
        #expect(try slot(locale: "en-US") == ["01-hero-iPhone-6.9-en_US.png"])
        #expect(try slot(locale: "de-DE") == ["01-hero-iPhone-6.9-de_DE.png"])
    }

    @Test func filesOneBatchIntoTheDeviceClassesTheNamesName() throws {
        try putInInbox(named: "01-phone-iPhone-6.9-en_US.png", width: 1290, height: 2796)
        try putInInbox(named: "01-pad-iPad-13-en_US.png", width: 2064, height: 2752)

        let project = try fixture.load()
        let outcome = try Inbox.file(Inbox.plan(in: project), version: "1.0", in: project)
        defer { empty(outcome.trashed) }

        #expect(try slot(deviceClassID: DeviceClass.iPhone69.id) == ["01-phone-iPhone-6.9-en_US.png"])
        #expect(try slot(deviceClassID: DeviceClass.iPad13.id) == ["01-pad-iPad-13-en_US.png"])
    }

    @Test func replacesMatchingScreenshotsInEachLanguage() throws {
        try fixture.writeScreenshot(
            locale: "en-US",
            deviceClassID: DeviceClass.iPhone69.id,
            named: "01-hero-iPhone-6.9-en_US.png",
            width: 1290,
            height: 2796
        )
        try fixture.writeScreenshot(
            locale: "de-DE",
            deviceClassID: DeviceClass.iPhone69.id,
            named: "01-hero-iPhone-6.9-de_DE.png",
            width: 1290,
            height: 2796
        )
        try putInInbox(named: "01-hero-iPhone-6.9-en_US.png")
        try putInInbox(named: "01-hero-iPhone-6.9-de_DE.png")

        let project = try fixture.load()
        let outcome = try Inbox.file(
            Inbox.plan(in: project),
            version: "1.0",
            in: project,
            replacingExisting: true
        )
        defer { empty(outcome.trashed) }

        #expect(try slot(locale: "en-US") == ["01-hero-iPhone-6.9-en_US.png"])
        #expect(try slot(locale: "de-DE") == ["01-hero-iPhone-6.9-de_DE.png"])
        #expect(outcome.trashed.count == 4)
    }

    /// A file filed before the naming rule existed is the same screenshot
    /// under a shorter name. Filing it again repairs the name rather than
    /// leaving the set holding the picture twice.
    @Test func replacesAnOlderShortenedName() throws {
        try fixture.writeScreenshot(
            locale: "en-US",
            deviceClassID: DeviceClass.iPhone69.id,
            named: "01-hero.png",
            width: 1290,
            height: 2796
        )
        try putInInbox(named: "01-hero-iPhone-6.9-en_US.png")

        let project = try fixture.load()
        let outcome = try Inbox.file(
            Inbox.plan(in: project),
            version: "1.0",
            in: project,
            replacingExisting: true
        )
        defer { empty(outcome.trashed) }

        #expect(try slot(locale: "en-US") == ["01-hero-iPhone-6.9-en_US.png"])
    }

    /// A filed image that is still in the inbox would be filed a second time
    /// the next time somebody files the folder.
    @Test func takesTheInboxCopyAwayOnceItIsFiled() throws {
        try putInInbox(named: "01-hero-iPhone-6.9-en_US.png")

        let project = try fixture.load()
        let outcome = try Inbox.file(Inbox.plan(in: project), version: "1.0", in: project)
        defer { empty(outcome.trashed) }

        #expect(try Inbox.waiting(in: project).isEmpty)
        #expect(outcome.trashed.count == 1)
    }

    /// A refused image is not a filed image, so it stays where a person can see
    /// it and do something about it.
    @Test func leavesARefusedImageInTheFolder() throws {
        try putInInbox(named: "01-hero-iPhone-6.9-en_US.png")
        try putInInbox(named: "01-small-iPhone-6.9-en_US.png", width: 800, height: 600)

        let project = try fixture.load()
        let outcome = try Inbox.file(Inbox.plan(in: project), version: "1.0", in: project)
        defer { empty(outcome.trashed) }

        #expect(outcome.filed == 1)
        #expect(try Inbox.waiting(in: project).map(\.fileName) == ["01-small-iPhone-6.9-en_US.png"])
    }

    /// Filing goes through `ContentWriter`, which checks every file before it
    /// moves one, so a set that is already full refuses the batch whole.
    @Test func refusesABatchThatWouldPassTheLimit() throws {
        for number in 1 ... 10 {
            try fixture.writeScreenshot(
                locale: "en-US", deviceClassID: DeviceClass.iPhone69.id,
                named: String(format: "%02d-old.png", number), width: 1290, height: 2796
            )
        }
        try putInInbox(named: "01-hero-iPhone-6.9-en_US.png")

        let project = try fixture.load()
        #expect(throws: ContentWriteError.self) {
            try Inbox.file(Inbox.plan(in: project), version: "1.0", in: project)
        }
        #expect(try Inbox.waiting(in: project).map(\.fileName) == ["01-hero-iPhone-6.9-en_US.png"])
    }
}
