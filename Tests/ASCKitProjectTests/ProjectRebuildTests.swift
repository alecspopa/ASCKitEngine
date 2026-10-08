import Foundation
import Testing
@testable import ASCKitProject

/// Rebuilding throws away work nobody can get back from App Store Connect, so
/// what it says it will remove has to be what it removes.
final class ProjectRebuildTests {
    let fixture: FixtureProject

    init() throws {
        fixture = try FixtureProject()
    }

    deinit {
        fixture.remove()
    }

    func config(sourceLocale: String = "en-US", locales: [String]? = nil) -> ProjectConfig {
        ProjectConfig(
            bundleID: "com.example.Demo",
            keyID: "ABC123",
            issuerID: "issuer",
            sourceLocale: sourceLocale,
            locales: locales ?? [sourceLocale],
            deviceClasses: [DeviceClass.iPhone69.id]
        )
    }

    /// A project with content in it, which is the only interesting case.
    func makeFullProject() throws -> URL {
        let folder = try ProjectScaffold.create(
            in: fixture.rootURL,
            config: config(locales: ["en-US", "de-DE"]),
            version: "1.0"
        )
        let project = try Project.load(at: folder)

        for locale in ["en-US", "de-DE"] {
            try ContentWriter.writeAppInformation(
                AppInformation(locale: locale, status: .approved, fields: goodFields()),
                version: "1.0",
                in: project
            )
            for number in 1 ... 2 {
                let directory = project.screenshotsURL(
                    version: "1.0",
                    locale: locale,
                    deviceClassID: DeviceClass.iPhone69.id
                )
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try PNGWriter.write(
                    to: directory.appending(path: String(format: "%02d-shot.png", number)),
                    width: 1290,
                    height: 2796,
                    hasAlpha: false,
                    seed: "\(locale)\(number)"
                )
            }
        }

        try FileManager.default.createDirectory(at: project.historyURL, withIntermediateDirectories: true)
        return folder
    }

    func goodFields() -> AppInformation.Fields {
        AppInformation.Fields(
            name: "Demo",
            keywords: "household,restock",
            description: "Know what you have.",
            supportUrl: "https://example.com/support",
            privacyPolicyUrl: "https://example.com/privacy"
        )
    }

    func names(in folder: URL) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: folder.path).sorted()
    }

    // MARK: - Saying what goes

    @Test func countsEverythingTheRebuildWouldTakeAway() throws {
        let folder = try makeFullProject()

        let plan = ProjectRebuild.plan(at: folder)
        #expect(plan.versions == ["1.0"])
        #expect(plan.languages == ["de-DE", "en-US"])
        #expect(plan.screenshotCount == 4)
        #expect(plan.hasHistory)
        #expect(plan.keyID == "ABC123")
        #expect(plan.isEmpty == false)
    }

    /// Named in the plan so a person can be shown what is on disk, rather than
    /// only a summary of it.
    @Test func namesEveryEntryInTheFolder() throws {
        let folder = try makeFullProject()

        let plan = ProjectRebuild.plan(at: folder)
        let named = Set(plan.entries.map(\.lastPathComponent))
        #expect(try named == Set(names(in: folder)))
        #expect(named.contains("asckit.json"))
        #expect(named.contains("versions"))
    }

    /// Handing back the configuration is what lets a rebuild start from what
    /// the project already said about itself, rather than from nothing.
    @Test func handsBackTheConfigurationItFound() throws {
        let folder = try makeFullProject()

        let plan = ProjectRebuild.plan(at: folder)
        #expect(plan.currentConfig?.bundleID == "com.example.Demo")
        #expect(plan.currentConfig?.locales == ["en-US", "de-DE"])
    }

    /// A language whose file will not parse is still a language about to be
    /// lost. Counting from the file names rather than the contents is what
    /// makes sure nothing goes unmentioned.
    @Test func countsALanguageWhoseFileIsBroken() throws {
        let folder = try makeFullProject()
        let broken = folder.appending(path: "versions/1.0/version-data/fr-FR.json")
        try Data("{ not json".utf8).write(to: broken)

        #expect(ProjectRebuild.plan(at: folder).languages.contains("fr-FR"))
    }

    /// Everything under the screenshots folder goes, whatever it is, so
    /// everything under it is counted.
    @Test func countsScreenshotsInEveryLanguageAndDeviceFolder() throws {
        let folder = try makeFullProject()
        let project = try Project.load(at: folder)

        let extra = project.screenshotsURL(
            version: "1.0",
            locale: "de-DE",
            deviceClassID: DeviceClass.iPad13.id
        )
        try FileManager.default.createDirectory(at: extra, withIntermediateDirectories: true)
        try PNGWriter.write(
            to: extra.appending(path: "01-tablet.png"),
            width: 2048, height: 2732, hasAlpha: false, seed: "tablet"
        )

        #expect(ProjectRebuild.plan(at: folder).screenshotCount == 5)
    }

    @Test func saysThereIsNothingToRemoveInAnEmptyFolder() throws {
        let empty = fixture.rootURL.appending(path: "empty")
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)

        let plan = ProjectRebuild.plan(at: empty)
        #expect(plan.isEmpty)
        #expect(plan.currentConfig == nil)
        #expect(plan.keyID == nil)
    }

    /// A folder that is not a project should still be describable, so the app
    /// can offer to scaffold into it rather than refusing to look. What is
    /// already in it is not a loss, because a rebuild never reaches it.
    @Test func describesAFolderWithNoProjectInIt() throws {
        let folder = fixture.rootURL.appending(path: "notAProject")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("hello".utf8).write(to: folder.appending(path: "notes.txt"))

        let plan = ProjectRebuild.plan(at: folder)
        #expect(plan.folderURL.lastPathComponent == ".asckit")
        #expect(plan.entries.isEmpty)
        #expect(plan.trash.isEmpty)
        #expect(plan.versions.isEmpty)
        #expect(plan.currentConfig == nil)
    }

    // MARK: - Only the project folder

    /// A repository: an Xcode project, source, and the listing in `.asckit`
    /// beside them. This is what a person picks now.
    func makeRepository() throws -> URL {
        let repository = fixture.rootURL.appending(path: "repo")
        try FileManager.default.createDirectory(
            at: repository.appending(path: "Demo.xcodeproj"),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: repository.appending(path: "Sources"),
            withIntermediateDirectories: true
        )
        try Data("app".utf8).write(to: repository.appending(path: "Sources/App.swift"))
        try Data("# Demo".utf8).write(to: repository.appending(path: "README.md"))

        try ProjectScaffold.create(in: repository, config: config(), version: "1.0")
        return repository
    }

    /// Given the repository, the plan is about `.asckit` and about nothing
    /// else in it.
    @Test func planningARepositoryFindsTheProjectFolderInside() throws {
        let repository = try makeRepository()

        let plan = ProjectRebuild.plan(at: repository)
        #expect(plan.folderURL.lastPathComponent == ".asckit")
        #expect(plan.currentConfig?.bundleID == "com.example.Demo")

        let named = Set(plan.entries.map(\.lastPathComponent))
        #expect(named.contains("asckit.json"))
        #expect(named.contains("Demo.xcodeproj") == false)
        #expect(named.contains("Sources") == false)
    }

    /// The bug this guards against: a rebuild that trashed the repository
    /// around the project rather than the project.
    @Test func leavesEverythingOutsideTheProjectFolderAlone() throws {
        let repository = try makeRepository()
        let plan = ProjectRebuild.plan(at: repository)

        let trashed = try ProjectRebuild.rebuild(plan, config: config(), version: "1.0")
        defer { for url in trashed {
            try? FileManager.default.removeItem(at: url)
        } }

        #expect(try names(in: repository).sorted() == [".asckit", "Demo.xcodeproj", "README.md", "Sources"])
        #expect(FileManager.default.fileExists(atPath: repository.appending(path: "Sources/App.swift").path))
        #expect(try Data(contentsOf: repository.appending(path: "README.md")) == Data("# Demo".utf8))
    }

    /// One item in the Trash called `.asckit`, rather than its contents loose
    /// beside whatever else is already in there.
    @Test func movesTheProjectFolderItselfWhenItSitsInsideARepository() throws {
        let repository = try makeRepository()
        let plan = ProjectRebuild.plan(at: repository)
        #expect(plan.trash.map(\.lastPathComponent) == [".asckit"])

        let trashed = try ProjectRebuild.rebuild(plan, config: config(), version: "2.0")
        defer { for url in trashed {
            try? FileManager.default.removeItem(at: url)
        } }

        #expect(trashed.count == 1)
        #expect(try Project.load(at: repository).versionNames() == ["2.0"])
    }

    /// A configuration file written by hand at the root of a repository. The
    /// project reads from there, and a rebuild still must not take the source
    /// beside it. Nothing is trashed, and the new project goes in `.asckit`.
    @Test func neverTrashesARepositoryEvenWithAConfigurationAtItsRoot() throws {
        let repository = fixture.rootURL.appending(path: "flat")
        try FileManager.default.createDirectory(
            at: repository.appending(path: "Demo.xcodeproj"),
            withIntermediateDirectories: true
        )
        try ProjectScaffold.write(into: repository, config: config(), version: "1.0")

        let plan = ProjectRebuild.plan(at: repository)
        #expect(plan.folderURL.lastPathComponent == ".asckit")
        #expect(plan.trash.isEmpty)

        try ProjectRebuild.rebuild(plan, config: config(), version: "1.0")
        #expect(FileManager.default.fileExists(atPath: repository.appending(path: "Demo.xcodeproj").path))
        #expect(FileManager.default.fileExists(
            atPath: repository.appending(path: ".asckit/asckit.json").path
        ))
    }

    /// A project folder with nothing in it yet is still the project folder.
    /// Reading it as a repository would put a project inside a project.
    @Test func staysInAProjectFolderThatIsEmpty() throws {
        for name in ProjectScaffold.knownFolderNames {
            let folder = fixture.rootURL.appending(path: name)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

            let plan = ProjectRebuild.plan(at: folder)
            #expect(plan.folderURL.standardizedFileURL == folder.standardizedFileURL)
            #expect(plan.trash.isEmpty)

            try ProjectRebuild.rebuild(plan, config: config(), version: "1.0")
            #expect(try Project.load(at: folder).config.bundleID == "com.example.Demo")
            #expect(FileManager.default.fileExists(
                atPath: folder.appending(path: ".asckit").path
            ) == false)
        }
    }

    /// Trashing the folder needs permission for the folder holding it, which a
    /// caller naming the project folder cannot be assumed to have. What is
    /// inside moves instead.
    @Test func movesTheContentsWhenTheProjectFolderIsTheOneItWasGiven() throws {
        let folder = try makeFullProject()

        let plan = ProjectRebuild.plan(at: folder)
        #expect(plan.folderURL.standardizedFileURL == folder.standardizedFileURL)
        #expect(plan.trash.map(\.lastPathComponent) == plan.entries.map(\.lastPathComponent))
    }

    /// Reading what would be lost must not be a way of losing it.
    @Test func writesNothingWhenOnlyPlanning() throws {
        let folder = try makeFullProject()
        let before = try names(in: folder)

        _ = ProjectRebuild.plan(at: folder)
        #expect(try names(in: folder) == before)
    }

    // MARK: - Rebuilding

    @Test func leavesAProjectAsFreshAsANewOne() throws {
        let folder = try makeFullProject()
        let plan = ProjectRebuild.plan(at: folder)

        try ProjectRebuild.rebuild(plan, config: config(), version: "2.0")

        let project = try Project.load(at: folder)
        #expect(try project.versionNames() == ["2.0"])

        let content = try ContentStore.load(version: "2.0", in: project)
        #expect(content.appInformation.keys.sorted() == ["en-US"])
        #expect(content.appInformation["en-US"]?.status == .draft)
        #expect(content.screenshots.isEmpty)
    }

    @Test func takesTheOldLanguagesAndScreenshotsAway() throws {
        let folder = try makeFullProject()
        let plan = ProjectRebuild.plan(at: folder)

        try ProjectRebuild.rebuild(plan, config: config(), version: "1.0")

        #expect(ProjectRebuild.plan(at: folder).screenshotCount == 0)
        #expect(ProjectRebuild.plan(at: folder).languages == ["en-US"])
        #expect(FileManager.default.fileExists(atPath: folder.appending(path: "history").path) == false)
    }

    @Test func writesTheReadmeAndInboxAgain() throws {
        let folder = try makeFullProject()
        try FileManager.default.removeItem(at: folder.appending(path: "README.md"))

        let plan = ProjectRebuild.plan(at: folder)
        try ProjectRebuild.rebuild(plan, config: config(), version: "1.0")

        #expect(FileManager.default.fileExists(atPath: folder.appending(path: "README.md").path))
        #expect(FileManager.default.fileExists(atPath: folder.appending(path: "inbox/.gitignore").path))
    }

    /// The folder is named by whoever made it, and an older project sits in one
    /// called `appstore`. A rebuild must not quietly move it.
    @Test func keepsTheFolderWhateverItIsCalled() throws {
        let folder = fixture.rootURL.appending(path: "appstore")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try ProjectScaffold.write(into: folder, config: config(), version: "1.0")

        let plan = ProjectRebuild.plan(at: folder)
        try ProjectRebuild.rebuild(plan, config: config(), version: "1.0")

        #expect(try Project.load(at: folder).config.bundleID == "com.example.Demo")
        #expect(FileManager.default.fileExists(
            atPath: fixture.rootURL.appending(path: "asckit").path
        ) == false)
    }

    /// A person who meant a different folder has to be able to undo it, so
    /// nothing is deleted outright.
    @Test func movesTheOldFilesToTheTrashRatherThanDeletingThem() throws {
        let folder = try makeFullProject()
        let plan = ProjectRebuild.plan(at: folder)

        let trashed = try ProjectRebuild.rebuild(plan, config: config(), version: "1.0")
        defer { for url in trashed {
            try? FileManager.default.removeItem(at: url)
        } }

        // Everything the plan named is still somewhere it can be got back from.
        #expect(trashed.count == plan.trash.count)
        #expect(trashed.allSatisfy { FileManager.default.fileExists(atPath: $0.path) })

        // And the old screenshots really did leave the project.
        #expect(ProjectRebuild.plan(at: folder).screenshotCount == 0)
    }

    @Test func startsFromTheConfigurationItIsGivenRatherThanTheOldOne() throws {
        let folder = try makeFullProject()
        let plan = ProjectRebuild.plan(at: folder)

        let changed = ProjectConfig(
            bundleID: "com.example.Different",
            keyID: "XYZ789",
            issuerID: nil,
            sourceLocale: "de-DE",
            locales: ["de-DE"],
            deviceClasses: [DeviceClass.iPad13.id]
        )
        try ProjectRebuild.rebuild(plan, config: changed, version: "1.0")

        let config = try Project.load(at: folder).config
        #expect(config.bundleID == "com.example.Different")
        #expect(config.keyID == "XYZ789")
        #expect(config.issuerID == nil)
        #expect(config.sourceLocale == "de-DE")
    }
}
