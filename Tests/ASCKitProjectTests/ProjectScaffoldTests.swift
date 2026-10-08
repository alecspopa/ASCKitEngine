import Foundation
import Testing
@testable import ASCKitProject

/// A new project has to be one the checker can already read.
final class ProjectScaffoldTests {
    let fixture: FixtureProject

    init() throws {
        fixture = try FixtureProject()
    }

    deinit {
        fixture.remove()
    }

    func config(sourceLocale: String = "en-US") -> ProjectConfig {
        ProjectConfig(
            bundleID: "com.example.Demo",
            keyID: "ABC123",
            issuerID: "issuer",
            sourceLocale: sourceLocale,
            locales: [sourceLocale],
            deviceClasses: [DeviceClass.iPhone69.id]
        )
    }

    @Test func writesAProjectTheToolCanOpen() throws {
        let folder = try ProjectScaffold.create(
            in: fixture.rootURL,
            config: config(),
            version: "1.0"
        )

        #expect(folder.lastPathComponent == ".asckit")

        let project = try Project.load(at: folder)
        #expect(project.config.bundleID == "com.example.Demo")
        #expect(try project.versionNames() == ["1.0"])
    }

    @Test func writesAFirstCopyFileForTheSourceLanguage() throws {
        let folder = try ProjectScaffold.create(
            in: fixture.rootURL,
            config: config(sourceLocale: "de-DE"),
            version: "2.1"
        )

        let content = try ContentStore.load(version: "2.1", in: Project.load(at: folder))
        #expect(content.appInformation["de-DE"] != nil)
    }

    /// Nothing has been written yet, so an empty listing must not be
    /// publishable by accident.
    @Test func startsTheFirstLanguageAsADraft() throws {
        let folder = try ProjectScaffold.create(
            in: fixture.rootURL,
            config: config(),
            version: "1.0"
        )

        let content = try ContentStore.load(version: "1.0", in: Project.load(at: folder))
        #expect(content.appInformation["en-US"]?.status == .draft)
        #expect(content.appInformation["en-US"]?.status.canPublish == false)
    }

    /// A new project is not finished, and the checker should say what is
    /// missing rather than pass it.
    @Test func makesAProjectTheCheckerReportsAsIncomplete() throws {
        let folder = try ProjectScaffold.create(
            in: fixture.rootURL,
            config: config(),
            version: "1.0"
        )

        let result = try Checker.check(project: Project.load(at: folder))
        #expect(result.errors.isEmpty == false)
        #expect(result.canPublish == false)
    }

    // MARK: - The README and the inbox

    @Test func writesAReadmeSayingHowTheFolderIsShaped() throws {
        let folder = try ProjectScaffold.create(in: fixture.rootURL, config: config(), version: "1.0")

        let text = try String(contentsOf: folder.appending(path: "README.md"), encoding: .utf8)
        #expect(text.contains(Project.informationFolderName))
        #expect(text.contains("ai_approved"))
        #expect(text.contains("inbox"))
    }

    /// A number that changes does not belong in a file that never does. The
    /// README points at `asckit check` rather than repeating the limits, so
    /// there is nothing to drift out of step with Limits.swift.
    @Test func keepsTheChangingNumbersOutOfTheReadme() throws {
        let folder = try ProjectScaffold.create(in: fixture.rootURL, config: config(), version: "1.0")

        let text = try String(contentsOf: folder.appending(path: "README.md"), encoding: .utf8)
        #expect(text.contains("asckit check"))

        for size in DeviceClass.all.flatMap(\.acceptedSizes) {
            #expect(text.contains(size.description) == false, "\(size) is in the README")
        }
        for field in MetadataField.allCases {
            guard let maximum = field.maximumLength else { continue }
            #expect(text.contains("| \(maximum) |") == false, "\(field) limit is in the README")
        }
    }

    /// The `.gitignore` is the one tracked file in the folder, so the folder
    /// survives a clone, and it is the rule that keeps everything else out.
    @Test func makesAnInboxGitKeepsButDoesNotCommit() throws {
        let folder = try ProjectScaffold.create(in: fixture.rootURL, config: config(), version: "1.0")

        let ignore = folder.appending(path: "inbox/.gitignore")
        let text = try String(contentsOf: ignore, encoding: .utf8)

        #expect(text.contains("\n*\n"))
        #expect(text.contains("!.gitignore"))
        #expect(text.contains("!.gitkeep"))
    }

    /// A person may have written their own notes into it.
    @Test func leavesAReadmeThatIsAlreadyThereAlone() throws {
        let parent = fixture.rootURL.appending(path: "somewhere")
        let folder = parent.appending(path: ProjectScaffold.folderName)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data("mine".utf8).write(to: folder.appending(path: "README.md"))

        _ = try ProjectScaffold.create(in: parent, config: config(), version: "1.0")

        let text = try String(contentsOf: folder.appending(path: "README.md"), encoding: .utf8)
        #expect(text == "mine")
    }

    /// Overwriting a configuration would take the key ids with it.
    @Test func refusesToWriteOverAProjectThatIsAlreadyThere() throws {
        _ = try ProjectScaffold.create(in: fixture.rootURL, config: config(), version: "1.0")

        #expect(throws: ScaffoldError.self) {
            try ProjectScaffold.create(in: fixture.rootURL, config: config(), version: "1.0")
        }
    }

    /// A project made before the rename has an `app-information` folder and
    /// keeps it. Renaming somebody's folder would move files git is tracking.
    @Test func writesIntoTheInformationFolderThatIsAlreadyThere() throws {
        let folder = fixture.rootURL.appending(path: ".asckit")
        let old = folder.appending(path: "versions/1.0/app-information")
        try FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)

        try ProjectScaffold.write(into: folder, config: config(), version: "1.0")

        let project = try Project.load(at: folder)
        #expect(project.informationURL(version: "1.0").lastPathComponent == "app-information")
        #expect(FileManager.default.fileExists(atPath: old.appending(path: "en-US.json").path))
        #expect(FileManager.default.fileExists(atPath: folder.appending(path: "versions/1.0/version-data").path) == false)
    }

    @Test func makesTheFoldersUnderTheVersionItIsGiven() throws {
        let folder = try ProjectScaffold.create(
            in: fixture.rootURL,
            config: config(),
            version: "3.2.1"
        )

        let informationFolder = folder.appending(path: "versions/3.2.1/version-data")
        #expect(FileManager.default.fileExists(atPath: informationFolder.path))
    }
}

extension ProjectScaffoldTests {
    /// The folder it returns is inside the one it was given, not the one it was
    /// given. A sandboxed caller's permission belongs to the folder somebody
    /// picked and reaches this one only while that permission is open, so
    /// anything wanting to bookmark it has to do so before then.
    @Test func returnsAFolderInsideTheOneItWasGiven() throws {
        let folder = try ProjectScaffold.create(
            in: fixture.rootURL,
            config: config(),
            version: "1.0"
        )

        #expect(folder != fixture.rootURL)
        #expect(folder.deletingLastPathComponent().path == fixture.rootURL.path)
        #expect(folder.lastPathComponent == ProjectScaffold.folderName)
    }
}
