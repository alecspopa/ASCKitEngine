import Foundation
import Testing
@testable import ASCKitProject

/// The registry that says where a project's data is, when it is not in the
/// repository.
final class ProjectLocationsTests {
    let fixture: FixtureProject

    init() throws {
        fixture = try FixtureProject()
    }

    deinit {
        fixture.remove()
    }

    var root: URL { fixture.rootURL.appending(path: "ASCKit") }

    func config(bundleID: String = "com.example.Demo") -> ProjectConfig {
        ProjectConfig(
            bundleID: bundleID,
            keyID: "ABC123",
            issuerID: "issuer",
            sourceLocale: "en-US",
            locales: ["en-US"],
            deviceClasses: [DeviceClass.iPhone69.id]
        )
    }

    /// A repository with an Xcode project building the apps given. A nil
    /// bundle identifier leaves the setting out, as an `.xcconfig` would.
    func makeRepository(named name: String, apps: [String?] = ["com.example.Demo"]) throws -> URL {
        let repository = fixture.rootURL.appending(path: name)
        let xcodeproj = repository.appending(path: "Demo.xcodeproj")
        try FileManager.default.createDirectory(at: xcodeproj, withIntermediateDirectories: true)

        let targets = apps.indices.map { "APP\($0)" }.joined(separator: ", ")
        let objects = apps.enumerated().map { index, bundleID in
            let setting = bundleID.map { "PRODUCT_BUNDLE_IDENTIFIER = \"\($0)\";" } ?? ""
            return """
            APP\(index) = {
                isa = PBXNativeTarget;
                name = Target\(index);
                productType = "com.apple.product-type.application";
                buildConfigurationList = LIST\(index);
            };
            LIST\(index) = {
                isa = XCConfigurationList;
                buildConfigurations = (RELEASE\(index));
            };
            RELEASE\(index) = {
                isa = XCBuildConfiguration;
                name = Release;
                buildSettings = { \(setting) MARKETING_VERSION = "1.0"; SDKROOT = iphoneos; };
            };
            """
        }.joined(separator: "\n")

        let pbxproj = """
        // !$*UTF8*$!
        {
            archiveVersion = 1;
            objectVersion = 77;
            rootObject = ROOT;
            objects = {
                ROOT = { isa = PBXProject; knownRegions = (en,); targets = (\(targets)); };
                \(objects)
            };
        }
        """
        try Data(pbxproj.utf8).write(to: xcodeproj.appending(path: "project.pbxproj"))
        return repository
    }

    /// A data folder in the root, with a project written in it.
    @discardableResult
    func makeData(named name: String, bundleID: String = "com.example.Demo") throws -> URL {
        try ProjectScaffold.create(at: root.appending(path: name), config: config(bundleID: bundleID), version: "1.0")
    }

    // MARK: - The file

    @Test func roundTripsThroughTheFile() throws {
        var locations = ProjectLocations(root: root)
        locations.register(bundleID: "com.example.Demo", data: root.appending(path: "Demo"), repo: fixture.rootURL)
        try locations.save()

        let loaded = try ProjectLocations.load(root: root)
        #expect(loaded.entries == locations.entries)
        #expect(loaded.dataURL(for: "com.example.Demo")?.lastPathComponent == "Demo")
    }

    @Test func aMissingFileIsAnEmptyRegistry() throws {
        let loaded = try ProjectLocations.load(root: root)
        #expect(loaded.entries.isEmpty)
    }

    @Test func anUnreadableFileThrows() throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: root.appending(path: ProjectLocations.fileName))

        #expect(throws: ProjectLocationsError.self) {
            try ProjectLocations.load(root: root)
        }
    }

    @Test func defaultRootIsDocumentsASCKit() {
        let home = URL(fileURLWithPath: "/Users/someone")
        #expect(ProjectLocations.defaultRoot(home: home).path == "/Users/someone/Documents/ASCKit")
    }

    // MARK: - Registering

    @Test func aFolderInTheRootIsStoredRelativeAndAnyOtherIsAbsolute() {
        var locations = ProjectLocations(root: root)
        let outside = fixture.rootURL.appending(path: "elsewhere").appending(path: "Demo")

        locations.register(bundleID: "a", data: root.appending(path: "A"), repo: fixture.rootURL.appending(path: "ra"))
        locations.register(bundleID: "b", data: outside, repo: fixture.rootURL.appending(path: "rb"))

        #expect(locations.entries["a"]?.folder == "A")
        #expect(locations.entries["a"]?.path == nil)
        #expect(locations.entries["b"]?.folder == nil)
        #expect(locations.entries["b"]?.path == outside.standardizedFileURL.path)
        #expect(locations.dataURL(for: "b")?.standardizedFileURL == outside.standardizedFileURL)
    }

    @Test func aRepositoryMovesBetweenEntries() {
        var locations = ProjectLocations(root: root)
        let repo = fixture.rootURL.appending(path: "repo")

        locations.register(bundleID: "a", data: root.appending(path: "A"), repo: repo)
        locations.register(bundleID: "b", data: root.appending(path: "B"), repo: repo)

        #expect(locations.entries["a"]?.repos == [])
        #expect(locations.entries["b"]?.repos == [repo.standardizedFileURL.path])
    }

    // MARK: - Resolving

    @Test func resolvesByRepositoryPath() throws {
        let repo = try makeRepository(named: "repo", apps: [nil])
        let data = try makeData(named: "Demo")
        var locations = ProjectLocations(root: root)
        locations.register(bundleID: "com.example.Demo", data: data, repo: repo)

        let resolution = try #require(locations.resolve(repo: repo))
        #expect(resolution.source == .registeredByRepo)
        #expect(resolution.dataURL.standardizedFileURL == data.standardizedFileURL)
        #expect(resolution.bundleID == "com.example.Demo")
    }

    @Test func resolvesByBundleID() throws {
        let repo = try makeRepository(named: "repo")
        let data = try makeData(named: "Demo")
        var locations = ProjectLocations(root: root)
        locations.register(bundleID: "com.example.Demo", data: data, repo: fixture.rootURL.appending(path: "other"))

        let resolution = try #require(locations.resolve(repo: repo))
        #expect(resolution.source == .registeredByBundleID)
        #expect(resolution.dataURL.lastPathComponent == "Demo")
    }

    @Test func resolvesByScanWhenTheRegistryIsLost() throws {
        let repo = try makeRepository(named: "repo")
        try makeData(named: "Demo")
        try makeData(named: "Other", bundleID: "com.example.Other")

        let resolution = try #require(ProjectLocations(root: root).resolve(repo: repo))
        #expect(resolution.source == .foundByScan)
        #expect(resolution.dataURL.lastPathComponent == "Demo")
        #expect(resolution.bundleID == "com.example.Demo")
    }

    @Test func fallsBackToAProjectFolderInTheRepository() throws {
        let repo = try makeRepository(named: "repo")
        try ProjectScaffold.create(in: repo, config: config(), version: "1.0")

        let resolution = try #require(ProjectLocations(root: root).resolve(repo: repo))
        #expect(resolution.source == .inRepo)
        #expect(resolution.dataURL.lastPathComponent == ".asckit")
    }

    @Test func resolvesToNothingWhenNothingIsThere() throws {
        let repo = try makeRepository(named: "repo")
        try makeData(named: "Other", bundleID: "com.example.Other")

        #expect(ProjectLocations(root: root).resolve(repo: repo) == nil)
    }

    @Test func findsAnAppWithNoBundleIDByRepositoryPath() throws {
        let repo = try makeRepository(named: "repo", apps: [nil])
        let data = try makeData(named: "Demo")

        #expect(ProjectLocations(root: root).resolve(repo: repo) == nil)

        var locations = ProjectLocations(root: root)
        locations.register(bundleID: "com.example.Demo", data: data, repo: repo)
        #expect(locations.resolve(repo: repo)?.source == .registeredByRepo)
    }

    @Test func twoAppsWithOneEntryResolveToThatEntry() throws {
        let repo = try makeRepository(named: "repo", apps: ["com.example.Demo", "com.example.Second"])
        let data = try makeData(named: "Demo")
        var locations = ProjectLocations(root: root)
        locations.register(bundleID: "com.example.Demo", data: data, repo: fixture.rootURL.appending(path: "other"))

        let resolution = try #require(locations.resolve(repo: repo))
        #expect(resolution.bundleID == "com.example.Demo")
        #expect(resolution.source == .registeredByBundleID)
    }

    // MARK: - Folder names

    @Test func aTakenNameGetsTheBundleID() {
        var locations = ProjectLocations(root: root)
        locations.register(bundleID: "com.example.One", data: root.appending(path: "Demo"), repo: fixture.rootURL)

        #expect(locations.folderName(forDisplayName: "Fresh", bundleID: "com.example.Two") == "Fresh")
        #expect(locations.folderName(forDisplayName: "Demo", bundleID: "com.example.Two") == "Demo (com.example.Two)")
        #expect(locations.folderName(forDisplayName: "Demo", bundleID: "com.example.One") == "Demo")
    }

    @Test func aFolderOnDiskCountsAsTaken() throws {
        try FileManager.default.createDirectory(at: root.appending(path: "Demo"), withIntermediateDirectories: true)

        let name = ProjectLocations(root: root).folderName(forDisplayName: "Demo", bundleID: "com.example.Demo")
        #expect(name == "Demo (com.example.Demo)")
    }

    @Test func slashesAndColonsLeaveTheName() {
        let name = ProjectLocations(root: root).folderName(forDisplayName: "A/B: C", bundleID: "x")
        #expect(name == "A-B- C")
    }

    // MARK: - New projects

    @Test func newProjectPointsAtTheRootForARepositoryWithNoProject() throws {
        let repo = try makeRepository(named: "repo")

        let found = try NewProject.read(in: repo, locations: ProjectLocations(root: root))
        #expect(found.destination.deletingLastPathComponent().standardizedFileURL.path == root.standardizedFileURL.path)
        #expect(found.alreadyAProject == false)
    }

    @Test func newProjectSeesARegisteredProject() throws {
        let repo = try makeRepository(named: "repo")
        let data = try makeData(named: "Demo")
        var locations = ProjectLocations(root: root)
        locations.register(bundleID: "com.example.Demo", data: data, repo: repo)

        let found = try NewProject.read(in: repo, locations: locations)
        #expect(found.alreadyAProject)
        #expect(found.destination.standardizedFileURL == data.standardizedFileURL)
    }

    // MARK: - Opening and scaffolding

    @Test func openingWithDataKeepsTheXcodeFolderAndMovesTheCache() throws {
        let repo = try makeRepository(named: "repo")
        let data = try makeData(named: "Demo")
        let cacheRoot = fixture.rootURL.appending(path: "caches")

        let project = try Project.open(repo: repo, data: data, cacheRoot: cacheRoot)
        #expect(project.xcodeFolderURL == repo)
        #expect(project.rootURL.standardizedFileURL.path == data.standardizedFileURL.path)
        #expect(project.cacheURL == cacheRoot.appending(path: "com.example.Demo"))
    }

    @Test func openingWithDataRefusesARepositoryWithNoXcodeProject() throws {
        let data = try makeData(named: "Demo")
        let empty = fixture.rootURL.appending(path: "empty")
        try FileManager.default.createDirectory(at: empty, withIntermediateDirectories: true)

        #expect(throws: ProjectError.self) {
            try Project.open(repo: empty, data: data, cacheRoot: nil)
        }
    }

    @Test func createAtWritesDirectlyAndMakesNoCache() throws {
        let folder = root.appending(path: "Demo")
        try ProjectScaffold.create(at: folder, config: config(), version: "1.0")

        let manager = FileManager.default
        #expect(manager.fileExists(atPath: folder.appending(path: "asckit.json").path))
        #expect(manager.fileExists(atPath: folder.appending(path: "inbox").path))
        #expect(manager.fileExists(atPath: folder.appending(path: "cache").path) == false)
        #expect(manager.fileExists(atPath: folder.appending(path: ".asckit").path) == false)

        #expect(throws: ScaffoldError.self) {
            try ProjectScaffold.create(at: folder, config: config(), version: "1.0")
        }
    }
}
