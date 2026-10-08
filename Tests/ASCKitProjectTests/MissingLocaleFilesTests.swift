import Foundation
import Testing
@testable import ASCKitProject

/// A language in the locale list with no file of its own is a gap ASCKit can
/// close by itself. The point is closing it without standing on anything a
/// person wrote.
final class MissingLocaleFilesTests {
    let fixture: FixtureProject

    init() throws {
        fixture = try FixtureProject()
        try fixture.writeConfig(config())
        try fixture.writeCopy(AppInformation(locale: "en-US", status: .approved))
    }

    deinit {
        fixture.remove()
    }

    func config(locales: [String] = ["en-US", "de-DE"]) -> ProjectConfig {
        ProjectConfig(
            bundleID: "com.example.Demo",
            keyID: "ABC123",
            issuerID: "issuer",
            sourceLocale: "en-US",
            locales: locales,
            deviceClasses: [DeviceClass.iPhone69.id]
        )
    }

    @Test func writesAFileForALanguageThatHasNone() throws {
        let written = try MissingLocaleFiles.write(in: fixture.load())

        #expect(written == ["de-DE"])
        #expect(try fixture.content().appInformation["de-DE"]?.locale == "de-DE")
    }

    /// An empty listing must never publish, so the file arrives as a draft with
    /// no words in it.
    @Test func writesAnEmptyDraft() throws {
        try MissingLocaleFiles.write(in: fixture.load())

        let information = try #require(try fixture.content().appInformation["de-DE"])
        #expect(information.status == .draft)
        #expect(information.fields.presentFields.isEmpty)
    }

    /// The warning this is here to answer: the validator wants a file for
    /// every name in the locale list.
    @Test func takesTheWarningAboutAMissingFileAway() throws {
        try MissingLocaleFiles.write(in: fixture.load())

        let layout = try fixture.problems().filter { $0.area == .layout }
        #expect(layout.isEmpty)
    }

    /// What is on disk may be a translation somebody is still working on.
    @Test func leavesAFileThatIsAlreadyThere() throws {
        try fixture.writeCopy(AppInformation(
            locale: "de-DE",
            status: .approved,
            fields: AppInformation.Fields(name: "Beispiel")
        ))

        let written = try MissingLocaleFiles.write(in: fixture.load())

        #expect(written.isEmpty)
        let information = try #require(try fixture.content().appInformation["de-DE"])
        #expect(information.status == .approved)
        #expect(information.fields.name == "Beispiel")
    }

    /// A file nothing can read is still somebody's file. Writing over it would
    /// take away the only copy of what it holds.
    @Test func leavesAFileThatCannotBeRead() throws {
        try fixture.writeRawCopy("{ not json", locale: "de-DE")

        let written = try MissingLocaleFiles.write(in: fixture.load())

        #expect(written.isEmpty)
        #expect(try fixture.content().unreadableInformation["de-DE"] != nil)
    }

    /// The checker reads the newest version, so that is the one whose gaps are
    /// worth closing. An older version is a listing that already went out.
    @Test func writesIntoTheNewestVersionOnly() throws {
        let older = FixtureProject.at(fixture.rootURL, version: "0.9")
        try older.writeCopy(AppInformation(locale: "en-US", status: .approved))
        let newer = FixtureProject.at(fixture.rootURL, version: "1.10")
        try newer.writeCopy(AppInformation(locale: "en-US", status: .approved))

        let written = try MissingLocaleFiles.write(in: fixture.load())

        #expect(written == ["de-DE"])
        #expect(try newer.content().appInformation["de-DE"] != nil)
        #expect(try older.content().appInformation["de-DE"] == nil)
    }

    /// A new version folder is made empty on purpose, and a file that arrived
    /// by itself is a file nobody read. The first thing in a version is
    /// somebody's decision.
    @Test func writesNothingIntoAVersionNobodyHasStarted() throws {
        let project = try fixture.load()
        try ContentWriter.createVersion("1.1", in: project)

        #expect(MissingLocaleFiles.write(in: project).isEmpty)
        let information = project.informationURL(version: "1.1")
        #expect(try FileManager.default.contentsOfDirectory(atPath: information.path).isEmpty)
    }

    /// A file written here would be the first thing in a version nobody has
    /// started, which says a version exists when none does.
    @Test func writesNothingWhenThereIsNoVersionFolder() throws {
        let fresh = try FixtureProject()
        defer { fresh.remove() }
        try fresh.writeConfig(config())

        #expect(try MissingLocaleFiles.write(in: fresh.load()).isEmpty)
        #expect(FileManager.default.fileExists(atPath: fresh.rootURL.appending(path: "versions").path) == false)
    }
}
