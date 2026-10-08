import ASCKitAPI
import Foundation
import Testing
@testable import ASCKitProject

/// App Store Connect opening a new version is the normal start of a release,
/// and the only sign of it on disk is a folder that does not exist yet. Saying
/// so is the whole point; saying it when the folders agree would be noise.
final class VersionDriftTests {
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

    func listing(version: String) -> RemoteListing {
        RemoteListing(
            appID: "app1",
            appName: "Demo",
            bundleID: "com.example.Demo",
            appInfoID: "info1",
            appInfoState: .prepareForSubmission,
            versionID: "v1",
            versionString: version,
            versionState: .prepareForSubmission,
            appInfoLocalizations: [:],
            versionLocalizations: [:],
            screenshotSets: []
        )
    }

    // MARK: - Comparing

    @Test func agreesWhenTheFolderIsThere() {
        let outcome = VersionDrift.compare(listing: listing(version: "1.0"), versions: ["1.0"])

        #expect(outcome == .agreed(version: "1.0"))
        #expect(outcome.versionToCreate == nil)
        #expect(outcome.problem(versionsPath: "versions") == nil)
    }

    @Test func namesTheVersionWithNoFolderAndTheNewestThereIs() {
        let outcome = VersionDrift.compare(listing: listing(version: "1.1"), versions: ["1.0"])

        #expect(outcome == .missingFolder(version: "1.1", newest: "1.0"))
        #expect(outcome.versionToCreate == "1.1")
    }

    /// 1.10 is a later version than 1.9, and the folder listing already sorts
    /// them that way. The newest one is the one worth naming.
    @Test func namesTheNewestFolderTheWayVersionNumbersRead() throws {
        for version in ["1.9", "1.10"] {
            try ContentWriter.createVersion(version, in: fixture.load())
        }
        let outcome = try VersionDrift.compare(listing: listing(version: "2.0"), project: fixture.load())

        #expect(outcome == .missingFolder(version: "2.0", newest: "1.10"))
    }

    @Test func saysSoWhenThereAreNoFoldersAtAll() throws {
        let outcome = try VersionDrift.compare(listing: listing(version: "1.0"), project: fixture.load())
        let problem = try #require(outcome.problem(versionsPath: "versions"))

        #expect(outcome == .missingFolder(version: "1.0", newest: nil))
        #expect(problem.message.english.contains("no version folders here yet"))
    }

    /// An error rather than a warning. Nothing can be read for a version with
    /// no folder, so a push has nothing to push.
    @Test func reportsAMissingFolderAsSomethingThatBlocksPublishing() throws {
        let outcome = VersionDrift.compare(listing: listing(version: "1.1"), versions: ["1.0"])
        let problem = try #require(outcome.problem(versionsPath: "versions"))

        #expect(problem.severity == .error)
        #expect(problem.message.english.contains("1.1"))
        #expect(problem.message.english.contains("The newest folder here is 1.0."))
        #expect(problem.fix?.english.contains("versions/1.1") == true)
    }

    @Test func namesThePathTheProjectActuallyUses() throws {
        let outcome = VersionDrift.compare(listing: listing(version: "1.1"), versions: [])
        let problem = try #require(outcome.problem(versionsPath: "releases"))

        #expect(problem.path == "releases")
        #expect(problem.fix?.english.contains("releases/1.1") == true)
    }

    // MARK: - Making the folder

    @Test func makesTheFolderAndLeavesItEmpty() throws {
        let project = try fixture.load()
        let folder = try ContentWriter.createVersion("1.1", in: project)

        #expect(try project.versionNames().contains("1.1"))
        #expect(FileManager.default.fileExists(atPath: folder.appending(path: Project.informationFolderName).path))
        #expect(try FileManager.default.contentsOfDirectory(
            atPath: project.informationURL(version: "1.1").path
        ).isEmpty)
    }

    /// The one thing this must never do is stand on work that is already there.
    @Test func refusesAVersionThatAlreadyHasAFolder() throws {
        let project = try fixture.load()
        try fixture.writeCopy(AppInformation(locale: "en-US", status: .approved))

        #expect(throws: ContentWriteError.self) {
            try ContentWriter.createVersion(fixture.version, in: project)
        }
        #expect(try ContentStore.load(version: fixture.version, in: project).appInformation["en-US"] != nil)
    }

    @Test func stopsAgreeingAsSoonAsTheFolderIsMade() throws {
        let project = try fixture.load()
        let before = try VersionDrift.compare(listing: listing(version: "1.1"), project: project)
        try ContentWriter.createVersion("1.1", in: project)
        let after = try VersionDrift.compare(listing: listing(version: "1.1"), project: project)

        #expect(before.versionToCreate == "1.1")
        #expect(after == .agreed(version: "1.1"))
    }
}
