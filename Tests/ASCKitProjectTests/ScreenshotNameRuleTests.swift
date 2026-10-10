import Foundation
import Testing
@testable import ASCKitProject

/// One rule for what a screenshot is called, and the two things that can
/// disagree with it: a file copied out of another language, and a file filed
/// before the rule existed.
///
/// The name is not only a label here. It goes to App Store Connect with the
/// image, and the next push looks for it there.
final class ScreenshotNameRuleTests {
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
    }

    deinit {
        fixture.remove()
    }

    /// A folder outside the project, standing in for `inbox`.
    func makeIncoming() throws -> URL {
        let url = fixture.rootURL.appending(path: "incoming-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @discardableResult
    func makeImage(in folder: URL, named fileName: String) throws -> URL {
        let url = folder.appending(path: fileName)
        try PNGWriter.write(to: url, width: 1290, height: 2796, hasAlpha: false, seed: fileName)
        return url
    }

    func slot() throws -> [String] {
        let directory = fixture.screenshotsDirectory(
            locale: "en-US", deviceClassID: DeviceClass.iPhone69.id
        )
        return try FileManager.default
            .contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasPrefix(".") == false }
            .sorted { $0.compare($1, options: .numeric) == .orderedAscending }
    }

    // MARK: - Writing a name

    /// The one name a copy cannot keep. The file says the language it came
    /// from, and the folder it lands in says another.
    @Test func renamesAFileThatCameFromAnotherLanguage() throws {
        try fixture.writeConfig(ProjectConfig(
            bundleID: "com.example.Demo",
            keyID: "ABC123",
            issuerID: "issuer",
            sourceLocale: "en-US",
            locales: ["en-US", "de-DE"],
            deviceClasses: [DeviceClass.iPhone69.id]
        ))

        let incoming = try makeIncoming()
        try makeImage(in: incoming, named: "03-shopping-iPhone-6.9-de_DE.png")

        try ContentWriter.addScreenshots(
            from: [incoming.appending(path: "03-shopping-iPhone-6.9-de_DE.png")],
            locale: "en-US",
            deviceClass: .iPhone69,
            at: .version("1.0"),
            in: fixture.load()
        )

        #expect(try slot() == ["01-shopping-iPhone-6.9-en_US.png"])
    }

    /// A file filed before the rule existed carries a shorter name. The next
    /// write to that set puts it right, so one folder never holds two rules.
    @Test func putsAnOlderShortenedNameRight() throws {
        try fixture.writeScreenshot(
            locale: "en-US", deviceClassID: DeviceClass.iPhone69.id,
            named: "01-hero.png", width: 1290, height: 2796
        )

        let incoming = try makeIncoming()
        try makeImage(in: incoming, named: "02-widgets-iPhone-6.9-en_US.png")

        try ContentWriter.addScreenshots(
            from: [incoming.appending(path: "02-widgets-iPhone-6.9-en_US.png")],
            locale: "en-US",
            deviceClass: .iPhone69,
            at: .version("1.0"),
            in: fixture.load()
        )

        #expect(try slot() == [
            "01-hero-iPhone-6.9-en_US.png", "02-widgets-iPhone-6.9-en_US.png"
        ])
    }

    // MARK: - Putting old names right

    @Test func repairsAFolderWrittenBeforeTheRule() throws {
        for (number, name) in ["hero", "shared"].enumerated() {
            try fixture.writeScreenshot(
                locale: "en-US", deviceClassID: DeviceClass.iPhone69.id,
                named: String(format: "%02d-\(name).png", number + 1), width: 1290, height: 2796
            )
        }

        let moved = try ContentWriter.repairNames(at: .version("1.0"), in: fixture.load())

        #expect(try slot() == [
            "01-hero-iPhone-6.9-en_US.png", "02-shared-iPhone-6.9-en_US.png"
        ])
        #expect(moved.map(\.from) == ["01-hero.png", "02-shared.png"])
    }

    /// A set already named by the rule is left exactly as it is, so running
    /// this twice is the same as running it once.
    @Test func renamesNothingInAFolderThatAlreadyFollowsTheRule() throws {
        try fixture.writeScreenshot(
            locale: "en-US", deviceClassID: DeviceClass.iPhone69.id,
            named: "01-hero-iPhone-6.9-en_US.png", width: 1290, height: 2796
        )

        #expect(try ContentWriter.repairNames(at: .version("1.0"), in: fixture.load()).isEmpty)
        #expect(try slot() == ["01-hero-iPhone-6.9-en_US.png"])
    }

    // MARK: - Saying so in the check

    /// The name goes to App Store Connect with the image, so a name ASCKit
    /// would not write is a name the next push cannot look for.
    @Test func warnsAboutAScreenshotThatIsNotNamedByTheRule() throws {
        try fixture.writeScreenshot(
            locale: "en-US", deviceClassID: DeviceClass.iPhone69.id,
            named: "01-hero.png", width: 1290, height: 2796
        )

        let problem = try #require(try fixture.problems().first {
            $0.kind == .screenshotsNamedWrong
        })
        #expect(problem.severity == .warning)
        #expect(problem.message.english.contains("01-hero.png"))
        #expect(problem.fix?.english.contains("asckit fix-names") == true)
    }
}
