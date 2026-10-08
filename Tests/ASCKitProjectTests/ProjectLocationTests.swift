import Foundation
import Testing
@testable import ASCKitProject

/// Where a project is found, now that opening one means picking the folder
/// with the `.xcodeproj` in it.
final class ProjectLocationTests {
    let fixture: FixtureProject

    init() throws {
        fixture = try FixtureProject()
    }

    deinit {
        fixture.remove()
    }

    func config() -> ProjectConfig {
        ProjectConfig(
            bundleID: "com.example.Demo",
            keyID: "ABC123",
            issuerID: "issuer",
            sourceLocale: "en-US",
            locales: ["en-US"],
            deviceClasses: [DeviceClass.iPhone69.id]
        )
    }

    /// A repository folder: an Xcode project, and a listing folder beside it.
    @discardableResult
    func makeRepository(projectFolderNamed name: String) throws -> URL {
        let repository = fixture.rootURL.appending(path: "repo-\(name)")
        try FileManager.default.createDirectory(
            at: repository.appending(path: "Demo.xcodeproj"),
            withIntermediateDirectories: true
        )

        let folder = repository.appending(path: name)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try ProjectScaffold.write(into: folder, config: config(), version: "1.0")
        return repository
    }

    // MARK: - Opening the folder with the Xcode project in it

    @Test func findsAProjectInTheHiddenFolder() throws {
        let repository = try makeRepository(projectFolderNamed: ".asckit")

        let project = try Project.load(at: repository)
        #expect(project.config.bundleID == "com.example.Demo")
        #expect(project.rootURL.lastPathComponent == ".asckit")
    }

    /// A project made before the folder was hidden keeps the folder it is in.
    /// Nothing renames it.
    @Test func findsAProjectInAFolderAnOlderVersionWrote() throws {
        for name in ["asckit", "appstore"] {
            let repository = try makeRepository(projectFolderNamed: name)

            let project = try Project.load(at: repository)
            #expect(project.rootURL.lastPathComponent == name)
        }
    }

    /// The hidden one wins, so a repository that has both is not ambiguous.
    @Test func prefersTheHiddenFolderWhenThereAreTwo() throws {
        let repository = try makeRepository(projectFolderNamed: "asckit")
        let hidden = repository.appending(path: ".asckit")
        try FileManager.default.createDirectory(at: hidden, withIntermediateDirectories: true)

        var newer = config()
        newer.bundleID = "com.example.Newer"
        try ProjectScaffold.write(into: hidden, config: newer, version: "1.0")

        #expect(try Project.load(at: repository).config.bundleID == "com.example.Newer")
    }

    // MARK: - Only a folder with an Xcode project

    /// The app and the command line tool both open with `open`, so both refuse
    /// the same folders.
    @Test func opensAFolderThatHoldsAnXcodeProject() throws {
        let repository = try makeRepository(projectFolderNamed: ".asckit")

        let project = try Project.open(at: repository)
        #expect(project.config.bundleID == "com.example.Demo")
    }

    /// ASCKit reads the app out of the `.xcodeproj`. The `.asckit` folder on
    /// its own holds none, so it is refused however good the files in it are.
    @Test func refusesTheProjectFolderOnItsOwn() throws {
        let repository = try makeRepository(projectFolderNamed: ".asckit")
        let inside = repository.appending(path: ".asckit")

        #expect(throws: ProjectError.self) {
            try Project.open(at: inside)
        }
        #expect(throws: ProjectError.self) {
            try Project.checkXcodeProject(in: inside)
        }
    }

    /// Two Xcode projects have no one answer for which app a listing is for,
    /// so a folder holding two is refused the same as a folder holding none.
    @Test func refusesAFolderHoldingTwoXcodeProjects() throws {
        let repository = try makeRepository(projectFolderNamed: ".asckit")
        try FileManager.default.createDirectory(
            at: repository.appending(path: "Other.xcodeproj"),
            withIntermediateDirectories: true
        )

        #expect(throws: ProjectError.self) {
            try Project.open(at: repository)
        }
    }

    /// The Xcode project is checked before the files are read, so the reason
    /// given is the one a person can act on.
    @Test func saysTheXcodeProjectIsMissingRatherThanTheConfiguration() throws {
        let empty = fixture.rootURL.appending(path: "nothing")
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)

        let error = #expect(throws: ProjectError.self) {
            try Project.open(at: empty)
        }
        #expect("\(error!)".contains(".xcodeproj"))
    }

    // MARK: - The older ways still work

    @Test func opensTheProjectFolderItself() throws {
        let repository = try makeRepository(projectFolderNamed: ".asckit")

        let project = try Project.load(at: repository.appending(path: ".asckit"))
        #expect(project.config.bundleID == "com.example.Demo")
    }

    @Test func opensTheConfigurationFileItself() throws {
        let repository = try makeRepository(projectFolderNamed: ".asckit")

        let project = try Project.load(
            at: repository.appending(path: ".asckit/asckit.json")
        )
        #expect(project.config.bundleID == "com.example.Demo")
    }

    @Test func reportsAFolderWithNothingInIt() throws {
        let empty = fixture.rootURL.appending(path: "empty")
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)

        #expect(throws: ProjectError.self) {
            try Project.load(at: empty)
        }
    }

    // MARK: - Where a version's text is

    @Test func putsAVersionsTextInTheVersionDataFolder() throws {
        let repository = try makeRepository(projectFolderNamed: ".asckit")
        let project = try Project.load(at: repository)

        #expect(project.informationURL(version: "1.0").lastPathComponent == "version-data")
    }

    /// A project written before the folder was renamed keeps the folder it has,
    /// and ASCKit reads and writes that one. Renaming it would move files git
    /// is tracking, for a name nobody asked to change.
    @Test func readsTheFolderAnOlderVersionWrote() throws {
        let repository = try makeRepository(projectFolderNamed: ".asckit")
        let project = try Project.load(at: repository)

        let old = project.versionURL("1.0").appending(path: "app-information")
        try FileManager.default.moveItem(
            at: project.versionURL("1.0").appending(path: "version-data"),
            to: old
        )

        let reread = try Project.load(at: repository)
        #expect(reread.informationURL(version: "1.0").lastPathComponent == "app-information")

        let content = try ContentStore.load(version: "1.0", in: reread)
        #expect(content.appInformation["en-US"] != nil)
        #expect(content.informationFolderName == "app-information")
    }

    /// The problem names the folder a person will find, not the one ASCKit
    /// would have written.
    @Test func namesTheFolderThatIsThereInAProblem() throws {
        let repository = try makeRepository(projectFolderNamed: ".asckit")
        let project = try Project.load(at: repository)

        try FileManager.default.moveItem(
            at: project.versionURL("1.0").appending(path: "version-data"),
            to: project.versionURL("1.0").appending(path: "app-information")
        )

        let reread = try Project.load(at: repository)
        let content = try ContentStore.load(version: "1.0", in: reread)
        let paths = Validator(config: reread.config).validate(content).compactMap(\.path)

        #expect(paths.contains { $0.contains("app-information") })
        #expect(paths.contains { $0.contains("version-data") } == false)
    }

    // MARK: - Where a new one goes

    @Test func putsANewProjectInTheHiddenFolder() throws {
        let repository = fixture.rootURL.appending(path: "fresh")
        try FileManager.default.createDirectory(at: repository, withIntermediateDirectories: true)

        #expect(Project.projectFolder(under: repository).lastPathComponent == ".asckit")
    }

    /// Scaffolding beside a project that already exists under an older name
    /// would leave two listings for one app, and nothing saying which is real.
    @Test func pointsAtTheProjectThatIsAlreadyThere() throws {
        let repository = try makeRepository(projectFolderNamed: "asckit")

        #expect(Project.projectFolder(under: repository).lastPathComponent == "asckit")
    }

    /// A folder of the right name with nothing in it is not a project, so a new
    /// one still goes where new ones go.
    @Test func ignoresAFolderWithNoConfigurationInIt() throws {
        let repository = fixture.rootURL.appending(path: "hollow")
        try FileManager.default.createDirectory(
            at: repository.appending(path: "appstore"),
            withIntermediateDirectories: true
        )

        #expect(Project.projectFolder(under: repository).lastPathComponent == ".asckit")
    }
}
