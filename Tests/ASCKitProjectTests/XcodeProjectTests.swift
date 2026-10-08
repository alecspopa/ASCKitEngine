import Foundation
import Testing
@testable import ASCKitProject

/// Reading an `.xcodeproj` is reading a file format Apple never promised to
/// keep, so these are written against real project files rather than against a
/// model of one.
final class XcodeProjectTests {
    let fixture: FixtureProject

    init() throws {
        fixture = try FixtureProject()
    }

    deinit {
        fixture.remove()
    }

    /// Writes an `.xcodeproj` with the parts this reads and nothing else.
    @discardableResult
    func writeProject(
        named name: String = "Demo",
        in folder: URL? = nil,
        knownRegions: [String] = ["en", "Base"],
        developmentRegion: String? = nil,
        targets: String? = nil
    ) throws -> URL {
        let parent = folder ?? fixture.rootURL
        let url = parent.appending(path: "\(name).xcodeproj")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)

        let body = targets ?? """
                APP = {
                    isa = PBXNativeTarget;
                    name = \(name);
                    productType = "com.apple.product-type.application";
                    buildConfigurationList = APPLIST;
                };
                APPLIST = {
                    isa = XCConfigurationList;
                    defaultConfigurationName = Release;
                    buildConfigurations = (DEBUG, RELEASE);
                };
                DEBUG = {
                    isa = XCBuildConfiguration;
                    name = Debug;
                    buildSettings = {
                        PRODUCT_BUNDLE_IDENTIFIER = "com.example.\(name).debug";
                        MARKETING_VERSION = 0.9;
                        SDKROOT = iphoneos;
                    };
                };
                RELEASE = {
                    isa = XCBuildConfiguration;
                    name = Release;
                    buildSettings = {
                        PRODUCT_BUNDLE_IDENTIFIER = "com.example.\(name)";
                        MARKETING_VERSION = 2.3;
                        INFOPLIST_KEY_CFBundleDisplayName = "\(name) The App";
                        ASSETCATALOG_COMPILER_APPICON_NAME = "\(name)Icon";
                        SDKROOT = iphoneos;
                    };
                };
        """

        let regions = knownRegions.map { "\($0)," }.joined(separator: "\n            ")
        let development = developmentRegion.map { "developmentRegion = \($0);" } ?? ""
        let pbxproj = """
        // !$*UTF8*$!
        {
            archiveVersion = 1;
            objectVersion = 77;
            rootObject = ROOT;
            objects = {
                ROOT = {
                    isa = PBXProject;
                    \(development)
                    knownRegions = (
                        \(regions)
                    );
                    targets = (APP, TESTS);
                };
        \(body)
                TESTS = {
                    isa = PBXNativeTarget;
                    name = "\(name)Tests";
                    productType = "com.apple.product-type.bundle.unit-test";
                    buildConfigurationList = APPLIST;
                };
            };
        }
        """
        try Data(pbxproj.utf8).write(to: url.appending(path: "project.pbxproj"))
        return url
    }

    /// A project with settings at both levels, and optionally an Info.plist,
    /// which is the shape the inheritance rules are about.
    @discardableResult
    func writeProjectInheriting(
        projectSettings: String,
        targetSettings: String,
        plist: [String: Any]? = nil
    ) throws -> URL {
        let parent = fixture.rootURL.appending(path: "inherit-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)

        if let plist {
            let sources = parent.appending(path: "Sources")
            try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
            let data = try PropertyListSerialization.data(
                fromPropertyList: plist, format: .xml, options: 0
            )
            try data.write(to: sources.appending(path: "Info.plist"))
        }

        let url = parent.appending(path: "Inherited.xcodeproj")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)

        let pbxproj = """
        // !$*UTF8*$!
        {
            archiveVersion = 1;
            objectVersion = 77;
            rootObject = ROOT;
            objects = {
                ROOT = {
                    isa = PBXProject;
                    knownRegions = (en);
                    targets = (APP);
                    buildConfigurationList = PROJECTLIST;
                };
                PROJECTLIST = {
                    isa = XCConfigurationList;
                    buildConfigurations = (PROJECTRELEASE);
                };
                PROJECTRELEASE = {
                    isa = XCBuildConfiguration;
                    name = Release;
                    buildSettings = { \(projectSettings) };
                };
                APP = {
                    isa = PBXNativeTarget;
                    name = Inherited;
                    productType = "com.apple.product-type.application";
                    buildConfigurationList = TARGETLIST;
                };
                TARGETLIST = {
                    isa = XCConfigurationList;
                    buildConfigurations = (TARGETRELEASE);
                };
                TARGETRELEASE = {
                    isa = XCBuildConfiguration;
                    name = Release;
                    buildSettings = { \(targetSettings) };
                };
            };
        }
        """
        try Data(pbxproj.utf8).write(to: url.appending(path: "project.pbxproj"))
        return url
    }

    // MARK: - Finding one

    @Test func findsTheOneProjectInAFolder() throws {
        let url = try writeProject()
        #expect(XcodeProject.find(in: fixture.rootURL) == url)
    }

    /// Two projects have no obvious answer, and picking wrong would scaffold a
    /// listing for the other app.
    @Test func findsNothingWhenThereAreTwoProjects() throws {
        try writeProject(named: "One")
        try writeProject(named: "Two")

        #expect(XcodeProject.find(in: fixture.rootURL) == nil)
    }

    @Test func findsNothingInAFolderWithNoProject() {
        #expect(XcodeProject.find(in: fixture.rootURL) == nil)
    }

    // MARK: - Reading one

    @Test func readsWhatTheAppCallsItself() throws {
        let url = try writeProject()
        let project = try XcodeProject.read(at: url)

        let app = try #require(project.apps.first)
        #expect(app.targetName == "Demo")
        #expect(app.displayName == "Demo The App")
        #expect(app.bundleID == "com.example.Demo")
        #expect(app.iconName == "DemoIcon")
    }

    // MARK: - Which target a listing is for

    @Test func picksTheTargetBuildingTheBundleTheListingPushesTo() throws {
        let url = try writeProject()
        let project = try XcodeProject.read(at: url)

        #expect(project.app(forBundleID: "com.example.Demo")?.targetName == "Demo")
    }

    /// A project building one app has one answer, whatever the configuration
    /// says. The bundle identifiers disagreeing is worth reporting, and it is
    /// not a reason to show no name and no icon.
    @Test func picksTheOnlyAppWhenTheBundleDoesNotMatch() throws {
        let url = try writeProject()
        let project = try XcodeProject.read(at: url)

        #expect(project.app(forBundleID: "com.example.Something")?.targetName == "Demo")
    }

    /// The version that reaches the App Store is the release one, not the
    /// debug one sitting next to it.
    @Test func readsTheReleaseVersionRatherThanTheDebugOne() throws {
        let url = try writeProject()
        let project = try XcodeProject.read(at: url)

        #expect(project.apps.first?.marketingVersion == "2.3")
        #expect(project.apps.first?.bundleID == "com.example.Demo")
    }

    @Test func leavesOutTestsAndOtherThingsThatAreNotApps() throws {
        let url = try writeProject()
        let project = try XcodeProject.read(at: url)

        #expect(project.apps.count == 1)
        #expect(project.apps.contains { $0.targetName.hasSuffix("Tests") } == false)
    }

    /// `Base` is where the storyboards live, not a language anybody reads.
    @Test func leavesBaseOutOfTheLanguages() throws {
        let url = try writeProject(knownRegions: ["en", "de", "Base"])
        let project = try XcodeProject.read(at: url)

        #expect(project.knownRegions == ["en", "de"])
    }

    /// The listing is written in the first language, and `knownRegions` holds
    /// the development language wherever it was added. `developmentRegion` is
    /// what says which one the app is written in.
    @Test func putsTheDevelopmentLanguageFirst() throws {
        let url = try writeProject(knownRegions: ["en", "Base", "de"], developmentRegion: "de")
        let project = try XcodeProject.read(at: url)

        #expect(project.knownRegions == ["de", "en"])
    }

    /// An older project file, and one written by hand, may say nothing about
    /// which language it is written in.
    @Test func keepsTheOrderWhenNothingNamesTheDevelopmentLanguage() throws {
        let url = try writeProject(knownRegions: ["en", "de"])
        let project = try XcodeProject.read(at: url)

        #expect(project.knownRegions == ["en", "de"])
    }

    @Test func fallsBackToTheTargetNameWhenNothingElseNamesIt() throws {
        let url = try writeProject(targets: """
                APP = {
                    isa = PBXNativeTarget;
                    name = Plain;
                    productType = "com.apple.product-type.application";
                    buildConfigurationList = APPLIST;
                };
                APPLIST = {
                    isa = XCConfigurationList;
                    buildConfigurations = (RELEASE);
                };
                RELEASE = {
                    isa = XCBuildConfiguration;
                    name = Release;
                    buildSettings = { SDKROOT = macosx; };
                };
        """)

        let app = try #require(try XcodeProject.read(at: url).apps.first)
        #expect(app.displayName == "Plain")
        #expect(app.marketingVersion == nil)
        #expect(app.bundleID == nil)
    }

    /// `PRODUCT_NAME = "$(TARGET_NAME)"` is what Xcode writes by default.
    @Test func resolvesTheTargetNameReference() throws {
        let url = try writeProject(targets: """
                APP = {
                    isa = PBXNativeTarget;
                    name = Referenced;
                    productType = "com.apple.product-type.application";
                    buildConfigurationList = APPLIST;
                };
                APPLIST = {
                    isa = XCConfigurationList;
                    buildConfigurations = (RELEASE);
                };
                RELEASE = {
                    isa = XCBuildConfiguration;
                    name = Release;
                    buildSettings = {
                        PRODUCT_NAME = "$(TARGET_NAME)";
                        SDKROOT = iphoneos;
                    };
                };
        """)

        #expect(try XcodeProject.read(at: url).apps.first?.displayName == "Referenced")
    }

    /// A setting defined in an xcconfig cannot be seen from here. Saying it is
    /// not known beats handing on a string with a dollar sign in it.
    @Test func saysAVersionItCannotResolveIsNotKnown() throws {
        let url = try writeProject(targets: """
                APP = {
                    isa = PBXNativeTarget;
                    name = Configured;
                    productType = "com.apple.product-type.application";
                    buildConfigurationList = APPLIST;
                };
                APPLIST = {
                    isa = XCConfigurationList;
                    buildConfigurations = (RELEASE);
                };
                RELEASE = {
                    isa = XCBuildConfiguration;
                    name = Release;
                    buildSettings = {
                        MARKETING_VERSION = "$(APP_VERSION)";
                        SDKROOT = iphoneos;
                    };
                };
        """)

        #expect(try XcodeProject.read(at: url).apps.first?.marketingVersion == nil)
    }

    /// A watch-only app builds an application and has no listing of its own.
    @Test func leavesOutAnAppForAPlatformTheAppStoreDoesNotList() throws {
        let url = try writeProject(targets: """
                APP = {
                    isa = PBXNativeTarget;
                    name = Watchy;
                    productType = "com.apple.product-type.application";
                    buildConfigurationList = APPLIST;
                };
                APPLIST = {
                    isa = XCConfigurationList;
                    buildConfigurations = (RELEASE);
                };
                RELEASE = {
                    isa = XCBuildConfiguration;
                    name = Release;
                    buildSettings = { SDKROOT = watchos; };
                };
        """)

        #expect(try XcodeProject.read(at: url).apps.isEmpty)
    }

    @Test func refusesAFolderThatIsNotAProject() throws {
        let url = fixture.rootURL.appending(path: "Nothing.xcodeproj")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)

        #expect(throws: XcodeProjectError.self) {
            try XcodeProject.read(at: url)
        }
    }

    // MARK: - Inheriting from the project

    /// A version set once for the whole project is what a lot of people do,
    /// and every target inherits it. Reading only the target's own settings
    /// reports no version at all.
    @Test func takesASettingTheProjectSetsAndTheTargetDoesNot() throws {
        let url = try writeProjectInheriting(
            projectSettings: """
                MARKETING_VERSION = 4.2;
                PRODUCT_BUNDLE_IDENTIFIER = "com.example.FromProject";
            """,
            targetSettings: "SDKROOT = iphoneos;"
        )

        let app = try #require(try XcodeProject.read(at: url).apps.first)
        #expect(app.marketingVersion == "4.2")
        #expect(app.bundleID == "com.example.FromProject")
    }

    /// What the target says wins, because that is what Xcode builds with.
    @Test func prefersWhatTheTargetSaysOverWhatTheProjectSays() throws {
        let url = try writeProjectInheriting(
            projectSettings: "MARKETING_VERSION = 4.2;",
            targetSettings: """
                MARKETING_VERSION = 9.9;
                SDKROOT = iphoneos;
            """
        )

        #expect(try XcodeProject.read(at: url).apps.first?.marketingVersion == "9.9")
    }

    // MARK: - Info.plist

    /// An older project keeps the name and the version in an Info.plist.
    @Test func readsWhatIsOnlyInTheInfoPlist() throws {
        let url = try writeProjectInheriting(
            projectSettings: "",
            targetSettings: """
                SDKROOT = iphoneos;
                INFOPLIST_FILE = "Sources/Info.plist";
            """,
            plist: [
                "CFBundleDisplayName": "Named In The Plist",
                "CFBundleShortVersionString": "3.1",
                "CFBundleIdentifier": "com.example.Plisted"
            ]
        )

        let app = try #require(try XcodeProject.read(at: url).apps.first)
        #expect(app.displayName == "Named In The Plist")
        #expect(app.marketingVersion == "3.1")
        #expect(app.bundleID == "com.example.Plisted")
    }

    /// `CFBundleShortVersionString = $(MARKETING_VERSION)` is what every recent
    /// template writes, so a version read out of a plist is usually a pointer
    /// back at a build setting rather than a number.
    @Test func followsAPlistValueBackToTheBuildSettingItPointsAt() throws {
        let url = try writeProjectInheriting(
            projectSettings: "",
            targetSettings: """
                SDKROOT = iphoneos;
                MARKETING_VERSION = 5.5;
                INFOPLIST_FILE = "Sources/Info.plist";
            """,
            plist: ["CFBundleShortVersionString": "$(MARKETING_VERSION)"]
        )

        #expect(try XcodeProject.read(at: url).apps.first?.marketingVersion == "5.5")
    }

    /// A reference to something set in an xcconfig, or in the environment,
    /// resolves to nothing here. Handing on a string with a dollar sign in it
    /// would write it into a configuration file and push it to the App Store.
    @Test func saysNothingRatherThanHandOnAnUnresolvedReference() throws {
        let url = try writeProjectInheriting(
            projectSettings: "",
            targetSettings: """
                SDKROOT = iphoneos;
                INFOPLIST_FILE = "Sources/Info.plist";
            """,
            plist: ["CFBundleShortVersionString": "$(FROM_AN_XCCONFIG)"]
        )

        #expect(try XcodeProject.read(at: url).apps.first?.marketingVersion == nil)
    }

    @Test func carriesOnWhenTheInfoPlistIsNotThere() throws {
        let url = try writeProjectInheriting(
            projectSettings: "",
            targetSettings: """
                SDKROOT = iphoneos;
                MARKETING_VERSION = 1.2;
                INFOPLIST_FILE = "Sources/Missing.plist";
            """
        )

        #expect(try XcodeProject.read(at: url).apps.first?.marketingVersion == "1.2")
    }

    /// A setting pointing at itself must not spin.
    @Test func givesUpOnAReferenceThatPointsAtItself() {
        let settings = ["A": "$(A)", "B": "$(C)", "C": "$(B)"]
        #expect(XcodeProject.resolve("$(A)", settings: settings) == nil)
        #expect(XcodeProject.resolve("$(B)", settings: settings) == nil)
    }

    // MARK: - A real one

    /// Written against a synthetic project everywhere else, so this reads the
    /// one in this repository. If Apple changes the format, this is what says so.
    @Test(.enabled(if: AppRepository.isPresent, AppRepository.skipReason))
    func readsTheProjectThisPackageLivesIn() throws {
        let repository = AppRepository.url

        let url = try #require(XcodeProject.find(in: repository), "no .xcodeproj at \(repository.path)")
        let project = try XcodeProject.read(at: url)

        let app = try #require(project.apps.first)
        #expect(app.targetName == "ASCKit")
        #expect(app.bundleID == "com.alecspopa.ASCKit")
        #expect(app.displayName == "ASCKit")
        #expect(app.marketingVersion != nil, "no version read from a real project")
        #expect(project.apps.count == 1, "found \(project.apps.map(\.targetName))")

        // Every app target this finds must be usable, or the scaffold has
        // nothing to write. A real project is where that stops being true.
        for app in project.apps {
            #expect(app.bundleID != nil, "\(app.targetName) has no bundle identifier")
            #expect(app.displayName.contains("$") == false, "\(app.targetName) name unresolved")
        }
    }
}
