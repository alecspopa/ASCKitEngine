import Foundation
import Testing
@testable import ASCKitProject

final class CheckerTests {
    let fixture: FixtureProject

    init() throws {
        fixture = try FixtureProject()
    }

    deinit {
        fixture.remove()
    }

    func writeConfig(locales: [String] = ["en-US"]) throws {
        try fixture.writeConfig(ProjectConfig(
            bundleID: "com.example.MyApp",
            keyID: "ABC123",
            locales: locales,
            deviceClasses: [DeviceClass.iPhone69.id]
        ))
    }

    /// The app has to be able to open a project that has nothing in it yet and
    /// say so, rather than refusing to open it.
    @Test func reportsAProjectWithNoVersionsInsteadOfFailing() throws {
        try writeConfig()
        let result = try fixture.check()

        #expect(result.versionString == nil)
        #expect(result.problems.contains { $0.kind == .noVersionsYet })
        #expect(result.canPublish, "nothing is wrong, there is just nothing there")
    }

    /// A configuration problem is worth reporting even when there is no content
    /// to check it against.
    @Test func checksTheConfigurationEvenWithNoVersions() throws {
        try writeConfig(locales: ["en-US", "ja-JP"])
        let result = try fixture.check()

        #expect(result.versionString == nil)
        #expect(result.errors.contains { $0.locale == "ja-JP" })
        #expect(result.canPublish == false)
    }

    @Test func checksTheNewestVersionWhenNoneIsNamed() throws {
        try writeConfig()
        for version in ["1.0", "1.9", "1.10"] {
            let project = FixtureProject.at(fixture.rootURL, version: version)
            try project.writeCopy(AppInformation(locale: "en-US", status: .approved))
        }
        #expect(try fixture.check().versionString == "1.10", "1.10 comes after 1.9, not before it")
    }

    @Test func checksTheVersionItIsAskedFor() throws {
        try writeConfig()
        for version in ["1.0", "1.1"] {
            let project = FixtureProject.at(fixture.rootURL, version: version)
            try project.writeCopy(AppInformation(locale: "en-US", status: .approved))
        }
        #expect(try fixture.check(version: "1.0").versionString == "1.0")
    }

    @Test func refusesAVersionThatIsNotThere() throws {
        try writeConfig()
        let project = FixtureProject.at(fixture.rootURL, version: "1.0")
        try project.writeCopy(AppInformation(locale: "en-US", status: .approved))

        #expect(throws: ProjectError.self) {
            _ = try fixture.check(version: "9.9")
        }
    }

    @Test func refusesAFolderWithNoConfigurationFile() throws {
        #expect(throws: ProjectError.self) {
            _ = try fixture.load()
        }
    }

    /// Both are things a person will drag onto the app window.
    @Test func opensEitherTheFolderOrTheConfigurationFileItself() throws {
        try writeConfig()

        let fromFolder = try Project.load(at: fixture.rootURL)
        let fromFile = try Project.load(at: fixture.rootURL.appending(path: Project.defaultConfigName))

        #expect(fromFolder.config == fromFile.config)
        #expect(fromFolder.rootURL == fromFile.rootURL)
    }
}

extension CheckerTests {
    /// The configuration used to be checked by both Checker and Validator, so
    /// every configuration problem was printed twice.
    @Test func reportsAConfigurationProblemOnlyOnce() throws {
        try writeConfig(locales: ["en-US", "ja-JP"])
        let project = FixtureProject.at(fixture.rootURL, version: "1.0")
        try project.writeCopy(AppInformation(locale: "en-US", status: .approved))

        let result = try fixture.check()
        let aboutJapanese = result.problems.filter { $0.locale == "ja-JP" && $0.area == .configuration }
        #expect(aboutJapanese.count == 1)
    }
}
