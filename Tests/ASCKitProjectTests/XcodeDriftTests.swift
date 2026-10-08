import Foundation
import Testing
@testable import ASCKitProject

/// The listing and the Xcode project drifting apart is worth saying. Saying it
/// when they have not is worse than silence, because a report full of noise is
/// a report nobody reads.
final class XcodeDriftTests {
    let fixture: FixtureProject

    init() throws {
        fixture = try FixtureProject()
    }

    deinit {
        fixture.remove()
    }

    /// A repository: an Xcode project, and `.asckit` beside it.
    func makeRepository(
        bundleID: String = "com.example.Demo",
        marketingVersion: String = "1.0",
        knownRegions: [String] = ["en-US"],
        listingLocales: [String] = ["en-US"],
        ignoredLocales: [String] = [],
        listingVersions: [String] = ["1.0"]
    ) throws -> URL {
        let repository = fixture.rootURL.appending(path: "repo-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: repository, withIntermediateDirectories: true)
        try writeXcodeProject(
            in: repository,
            bundleID: bundleID,
            marketingVersion: marketingVersion,
            knownRegions: knownRegions
        )

        let folder = repository.appending(path: ProjectScaffold.folderName)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let config = ProjectConfig(
            bundleID: "com.example.Demo",
            keyID: "ABC123",
            issuerID: "issuer",
            sourceLocale: listingLocales[0],
            locales: listingLocales,
            ignoredLocales: ignoredLocales,
            deviceClasses: [DeviceClass.iPhone69.id]
        )
        for version in listingVersions {
            try ProjectScaffold.write(into: folder, config: config, version: version)
        }
        return repository
    }

    func writeXcodeProject(
        in folder: URL,
        bundleID: String,
        marketingVersion: String,
        knownRegions: [String]
    ) throws {
        let url = folder.appending(path: "Demo.xcodeproj")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)

        let regions = knownRegions.map { "\($0)," }.joined(separator: " ")
        let pbxproj = """
        // !$*UTF8*$!
        {
            archiveVersion = 1;
            objectVersion = 77;
            rootObject = ROOT;
            objects = {
                ROOT = {
                    isa = PBXProject;
                    knownRegions = (\(regions));
                    targets = (APP);
                };
                APP = {
                    isa = PBXNativeTarget;
                    name = Demo;
                    productType = "com.apple.product-type.application";
                    buildConfigurationList = LIST;
                };
                LIST = {
                    isa = XCConfigurationList;
                    buildConfigurations = (RELEASE);
                };
                RELEASE = {
                    isa = XCBuildConfiguration;
                    name = Release;
                    buildSettings = {
                        PRODUCT_BUNDLE_IDENTIFIER = "\(bundleID)";
                        MARKETING_VERSION = "\(marketingVersion)";
                        SDKROOT = iphoneos;
                    };
                };
            };
        }
        """
        try Data(pbxproj.utf8).write(to: url.appending(path: "project.pbxproj"))
    }

    func problems(in repository: URL) throws -> [Problem] {
        try Checker.check(project: Project.load(at: repository)).problems
    }

    /// The rules that read the Xcode project.
    static let driftKinds: Set<Problem.Kind> = regionKinds.union([
        .versionFolderMissingForXcode, .bundleIDMismatch
    ])

    /// The two rules about a language the app is built in.
    static let regionKinds: Set<Problem.Kind> = [.appRegionNotListed, .appRegionNoneListed]

    // MARK: - Saying nothing when they agree

    @Test func saysNothingWhenTheProjectAndTheListingAgree() throws {
        let repository = try makeRepository()

        let drift = try problems(in: repository).filter { Self.driftKinds.contains($0.kind) }
        #expect(drift.isEmpty, "unexpected: \(drift.map(\.message.english))")
    }

    /// A listing folder with no Xcode project beside it is every project made
    /// before this existed. It must report nothing at all.
    @Test func saysNothingWhenThereIsNoXcodeProject() throws {
        try fixture.writeConfig(ProjectConfig(
            bundleID: "com.example.Demo",
            keyID: "ABC123",
            issuerID: "issuer",
            sourceLocale: "en-US",
            locales: ["en-US"],
            deviceClasses: [DeviceClass.iPhone69.id]
        ))

        let drift = try fixture.problems().filter { Self.driftKinds.contains($0.kind) }
        #expect(drift.isEmpty)
    }

    // MARK: - Version

    @Test func saysWhenXcodeMovedOnToAVersionTheListingHasNoWordsFor() throws {
        let repository = try makeRepository(marketingVersion: "1.1", listingVersions: ["1.0"])

        let problem = try #require(try problems(in: repository).first {
            $0.kind == .versionFolderMissingForXcode
        })
        #expect(problem.severity == .warning)
        #expect(problem.message.english.contains("1.1"))
        #expect(problem.fix?.english.contains("Create version 1.1 on App Store Connect") == true)
    }

    /// Xcode moving first is the normal way round. A person part way through a
    /// release should not be told their project is broken for being part way
    /// through.
    @Test func makesTheVersionAWarningRatherThanAnError() throws {
        let repository = try makeRepository(marketingVersion: "2.0", listingVersions: ["1.0"])

        let result = try Checker.check(project: Project.load(at: repository))
        #expect(result.errors.contains { $0.kind == .versionFolderMissingForXcode } == false)
    }

    @Test func saysNothingWhenTheVersionFolderIsThere() throws {
        let repository = try makeRepository(marketingVersion: "1.1", listingVersions: ["1.0", "1.1"])

        #expect(try problems(in: repository).contains { $0.kind == .versionFolderMissingForXcode } == false)
    }

    // MARK: - Bundle identifier

    /// The one that is an error. A push against the wrong bundle identifier
    /// goes to a different app.
    @Test func refusesToLetTheListingPointAtADifferentApp() throws {
        let repository = try makeRepository(bundleID: "com.example.Other")

        let problem = try #require(try problems(in: repository).first { $0.kind == .bundleIDMismatch })
        #expect(problem.severity == .error)
        #expect(problem.message.english.contains("com.example.Other"))
        #expect(problem.message.english.contains("com.example.Demo"))
    }

    // MARK: - Languages

    @Test func saysWhenTheAppGainedALanguageTheListingHasNot() throws {
        let repository = try makeRepository(
            knownRegions: ["en-US", "de"],
            listingLocales: ["en-US"]
        )

        let problem = try #require(try problems(in: repository).first { $0.kind == .appRegionNotListed })
        #expect(problem.severity == .warning)
        #expect(problem.locale == "de-DE")
        #expect(problem.fix?.english.contains("de-DE") == true)
    }

    /// An ignored language is an answer to this warning rather than a case of
    /// it. The app is built in Romanian, the store page never will be, and
    /// saying so once has to stop the run asking again.
    @Test func saysNothingAboutALanguageTheListingIgnores() throws {
        let repository = try makeRepository(
            knownRegions: ["en-US", "ro"],
            listingLocales: ["en-US", "ro"],
            ignoredLocales: ["ro"]
        )

        let drift = try problems(in: repository).filter { Self.regionKinds.contains($0.kind) }
        #expect(drift.isEmpty, "unexpected: \(drift.map(\.message.english))")
    }

    /// An ambiguous region is satisfied by any one of its choices. An app built
    /// in `en` with a listing in `en-GB` is not missing anything.
    @Test func acceptsAnyOneChoiceForAnAmbiguousLanguage() throws {
        let repository = try makeRepository(
            knownRegions: ["en"],
            listingLocales: ["en-GB"]
        )

        #expect(try problems(in: repository).contains { Self.regionKinds.contains($0.kind) } == false)
    }

    @Test func namesTheChoicesWhenAnAmbiguousLanguageIsMissingEntirely() throws {
        let repository = try makeRepository(
            knownRegions: ["fr"],
            listingLocales: ["en-US"]
        )

        let problem = try #require(try problems(in: repository).first { $0.kind == .appRegionNoneListed })
        #expect(problem.message.english.contains("fr-CA"))
        #expect(problem.message.english.contains("fr-FR"))
    }

    /// A listing may ship a language the app does not, which is a translated
    /// store page for an app in English. That is a choice, not a mistake.
    @Test func saysNothingAboutAListingLanguageTheAppDoesNotHave() throws {
        let repository = try makeRepository(
            knownRegions: ["en-US"],
            listingLocales: ["en-US", "de-DE"]
        )

        #expect(try problems(in: repository).contains { Self.regionKinds.contains($0.kind) } == false)
    }
}
