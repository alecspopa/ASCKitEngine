import Foundation
import Testing
@testable import ASCKitProject

/// Reading the JSON project format Xcode 27.2 writes.
///
/// The fixtures here are written the way `xcprojformatter` prints a project:
/// JSON5 with a comma after the last item of every list. Apple's
/// `xcode-project-format` package is what says which key means what.
final class XcodeProjectJSONTests {
    let fixture: FixtureProject

    init() throws {
        fixture = try FixtureProject()
    }

    deinit {
        fixture.remove()
    }

    // MARK: - Writing one

    /// Writes an `.xcodeproj` holding a `project.xcproj` and nothing else.
    @discardableResult
    func writeProject(
        named name: String = "Demo",
        in folder: URL? = nil,
        body: String? = nil
    ) throws -> URL {
        let parent = folder ?? fixture.rootURL
        let url = parent.appending(path: "\(name).xcodeproj")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)

        let json = body ?? """
        {
          "default-configuration": "Release",
          "configurations": [
            "Debug",
            "Release",
          ],
          "localizations": {
            "development": "en",
            "supported": [
              "de",
            ],
          },
          "files": [
          ],
          "targets": [
            {
              "name": "\(name)",
              "id": "0000000000000000000000A1",
              "product-type": "application",
              "build-settings": {
                "ASSETCATALOG_COMPILER_APPICON_NAME": "\(name)Icon",
                "INFOPLIST_KEY_CFBundleDisplayName": "\(name) The App",
                "MARKETING_VERSION": "2.3",
                "PRODUCT_BUNDLE_IDENTIFIER": "com.example.\(name)",
                "PRODUCT_BUNDLE_IDENTIFIER[config=Debug]": "com.example.\(name).debug",
                "SDKROOT": "iphoneos",
              },
            }, {
              "name": "\(name)Tests",
              "id": "0000000000000000000000A2",
              "product-type": "bundle.unit-test",
            },
          ],
          "build-settings": {
          },
        }
        """

        try Data(json.utf8).write(to: url.appending(path: "project.xcproj"))
        return url
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
        #expect(app.marketingVersion == "2.3")
    }

    @Test func leavesOutTestsAndOtherThingsThatAreNotApps() throws {
        let url = try writeProject()
        let project = try XcodeProject.read(at: url)

        #expect(project.apps.count == 1)
        #expect(project.apps.contains { $0.targetName.hasSuffix("Tests") } == false)
    }

    /// The development language is not in `supported`, so it is put back at the
    /// front of the list the old format wrote in one piece.
    @Test func readsTheDevelopmentLanguageAndTheRest() throws {
        let url = try writeProject(body: projectFile(localizations: """
          "localizations": {
            "development": "en",
            "supported": [
              "de",
              "ja",
            ],
          },
        """))

        #expect(try XcodeProject.read(at: url).knownRegions == ["en", "de", "ja"])
    }

    @Test func leavesBaseOutOfTheLanguages() throws {
        let url = try writeProject(body: projectFile(localizations: """
          "localizations": {
            "development": "en",
            "supported": [
              "Base",
              "de",
            ],
          },
        """))

        #expect(try XcodeProject.read(at: url).knownRegions == ["en", "de"])
    }

    /// A file written by hand can name the same language twice. Showing it
    /// twice would ask a person to pick a store locale for it twice.
    @Test func namesALanguageOnce() throws {
        let url = try writeProject(body: projectFile(localizations: """
          "localizations": {
            "development": "en",
            "supported": [
              "en",
              "de",
            ],
          },
        """))

        #expect(try XcodeProject.read(at: url).knownRegions == ["en", "de"])
    }

    // MARK: - Build setting conditions

    /// The version that reaches the App Store is the release one. A key naming
    /// the debug configuration belongs to a build nobody uploads.
    @Test func takesTheValueForTheDefaultConfiguration() throws {
        let project = try XcodeProject.read(at: writeProject())

        #expect(project.apps.first?.bundleID == "com.example.Demo")
    }

    /// A key naming the configuration wins over the same key with no condition,
    /// which is how Xcode builds it.
    @Test func prefersTheConditionalValueOverThePlainOne() throws {
        let url = try writeProject(body: projectFile(settings: """
            "MARKETING_VERSION": "1.0",
            "MARKETING_VERSION[config=Release]": "4.5",
            "SDKROOT": "iphoneos",
        """))

        #expect(try XcodeProject.read(at: url).apps.first?.marketingVersion == "4.5")
    }

    @Test func readsTheConfigurationTheProjectCallsItsDefault() throws {
        let url = try writeProject(body: projectFile(
            defaultConfiguration: "Shipping",
            settings: """
                "MARKETING_VERSION[config=Debug]": "1.0",
                "MARKETING_VERSION[config=Shipping]": "7.7",
                "SDKROOT": "iphoneos",
            """
        ))

        #expect(try XcodeProject.read(at: url).apps.first?.marketingVersion == "7.7")
    }

    /// `[config=*]` matches whatever is being built.
    @Test func takesAConditionThatNamesEveryConfiguration() throws {
        let url = try writeProject(body: projectFile(settings: """
            "MARKETING_VERSION[config=*]": "3.3",
            "SDKROOT": "iphoneos",
        """))

        #expect(try XcodeProject.read(at: url).apps.first?.marketingVersion == "3.3")
    }

    /// Which SDK the app is built for is not known here, so a value held back
    /// by one is a guess. Xcode writes these for the display name and the
    /// status bar, and a project can write one for anything.
    @Test func leavesOutAValueHeldBackByAnSDK() throws {
        let url = try writeProject(body: projectFile(settings: """
            "MARKETING_VERSION[sdk=iphoneos*]": "9.9",
            "SDKROOT": "iphoneos",
        """))

        #expect(try XcodeProject.read(at: url).apps.first?.marketingVersion == nil)
    }

    @Test func leavesOutAValueForAnotherConfiguration() throws {
        let url = try writeProject(body: projectFile(settings: """
            "MARKETING_VERSION[config=Debug]": "0.9",
            "SDKROOT": "iphoneos",
        """))

        #expect(try XcodeProject.read(at: url).apps.first?.marketingVersion == nil)
    }

    /// A setting can hold a list, and everything reading one here wants the
    /// string Xcode would build from it. A dropped list would leave no platform
    /// at all, and a target with no platform is kept.
    @Test func joinsAListSettingIntoOneString() throws {
        let url = try writeProject(body: projectFile(settings: """
            "SUPPORTED_PLATFORMS": [
              "watchos",
              "watchsimulator",
            ],
        """))

        #expect(try XcodeProject.read(at: url).apps.isEmpty)
    }

    // MARK: - Inheriting from the project

    @Test func takesASettingTheProjectSetsAndTheTargetDoesNot() throws {
        let url = try writeProject(body: projectFile(
            settings: "\"SDKROOT\": \"iphoneos\",",
            projectSettings: """
                "MARKETING_VERSION": "4.2",
                "PRODUCT_BUNDLE_IDENTIFIER": "com.example.FromProject",
            """
        ))

        let app = try #require(try XcodeProject.read(at: url).apps.first)
        #expect(app.marketingVersion == "4.2")
        #expect(app.bundleID == "com.example.FromProject")
    }

    @Test func prefersWhatTheTargetSaysOverWhatTheProjectSays() throws {
        let url = try writeProject(body: projectFile(
            settings: """
                "MARKETING_VERSION": "9.9",
                "SDKROOT": "iphoneos",
            """,
            projectSettings: "\"MARKETING_VERSION\": \"4.2\","
        ))

        #expect(try XcodeProject.read(at: url).apps.first?.marketingVersion == "9.9")
    }

    // MARK: - Targets that are not apps

    /// An aggregate target builds nothing of its own, whatever it is called.
    @Test func leavesOutATargetThatIsNotNative() throws {
        let url = try writeProject(body: """
        {
          "default-configuration": "Release",
          "localizations": { "development": "en" },
          "files": [
          ],
          "targets": [
            {
              "name": "Everything",
              "id": "0000000000000000000000B1",
              "kind": "aggregate",
              "product-type": "application",
              "build-settings": {
                "SDKROOT": "iphoneos",
              },
            },
          ],
        }
        """)

        #expect(try XcodeProject.read(at: url).apps.isEmpty)
    }

    /// A product type Apple does not own keeps its whole name, under another
    /// key. Nothing with one of those has an App Store listing.
    @Test func leavesOutATargetWithAProductTypeOfItsOwn() throws {
        let url = try writeProject(body: """
        {
          "default-configuration": "Release",
          "localizations": { "development": "en" },
          "files": [
          ],
          "targets": [
            {
              "name": "Odd",
              "id": "0000000000000000000000B2",
              "full-product-type": "com.example.product-type.application",
              "build-settings": {
                "SDKROOT": "iphoneos",
              },
            },
          ],
        }
        """)

        #expect(try XcodeProject.read(at: url).apps.isEmpty)
    }

    @Test func leavesOutAnAppForAPlatformTheAppStoreDoesNotList() throws {
        let url = try writeProject(body: projectFile(settings: "\"SDKROOT\": \"watchos\","))

        #expect(try XcodeProject.read(at: url).apps.isEmpty)
    }

    // MARK: - What JSON5 allows and JSON does not

    /// Xcode prints a comma after the last item of every list, and a person can
    /// leave a comment in the file. A plain JSON reader refuses both.
    @Test func readsCommentsAndTrailingCommas() throws {
        let url = try writeProject(body: """
        // What this project builds.
        {
          /* Xcode writes Release here. */
          "default-configuration": "Release",
          "localizations": { "development": "en" },
          "files": [
          ],
          "targets": [
            {
              "name": "Commented",
              "id": "0000000000000000000000C1",
              "product-type": "application",
              "build-settings": {
                "MARKETING_VERSION": "6.1", // The one being worked on.
                "PRODUCT_BUNDLE_IDENTIFIER": "com.example.Commented",
                "SDKROOT": "iphoneos",
              },
            },
          ],
        }
        """)

        let app = try #require(try XcodeProject.read(at: url).apps.first)
        #expect(app.targetName == "Commented")
        #expect(app.marketingVersion == "6.1")
        #expect(app.bundleID == "com.example.Commented")
    }

    // MARK: - Info.plist

    @Test func readsWhatIsOnlyInTheInfoPlist() throws {
        let sources = fixture.rootURL.appending(path: "Sources")
        try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
        let plist = try PropertyListSerialization.data(
            fromPropertyList: [
                "CFBundleDisplayName": "Named In The Plist",
                "CFBundleShortVersionString": "$(MARKETING_VERSION)",
                "CFBundleIdentifier": "com.example.Plisted"
            ],
            format: .xml,
            options: 0
        )
        try plist.write(to: sources.appending(path: "Info.plist"))

        let url = try writeProject(body: projectFile(settings: """
            "INFOPLIST_FILE": "Sources/Info.plist",
            "MARKETING_VERSION": "3.1",
            "SDKROOT": "iphoneos",
        """))

        let app = try #require(try XcodeProject.read(at: url).apps.first)
        #expect(app.displayName == "Named In The Plist")
        #expect(app.marketingVersion == "3.1")
        #expect(app.bundleID == "com.example.Plisted")
    }

    // MARK: - Refusing one

    @Test func refusesAProjectFileThatIsNotJSON() throws {
        let url = fixture.rootURL.appending(path: "Broken.xcodeproj")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try Data("not a project at all".utf8).write(to: url.appending(path: "project.xcproj"))

        #expect(throws: XcodeProjectError.self) {
            try XcodeProject.read(at: url)
        }
    }

    /// JSON that parses and says nothing about a project is still not one.
    @Test func refusesJSONThatIsNotAProject() throws {
        let url = fixture.rootURL.appending(path: "Other.xcodeproj")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try Data(#"{ "name": "something else" }"#.utf8)
            .write(to: url.appending(path: "project.xcproj"))

        #expect(throws: XcodeProjectError.self) {
            try XcodeProject.read(at: url)
        }
    }

    // MARK: - Both files in one folder

    /// A folder part way through the change of format holds both files. The
    /// JSON one is what Xcode writes now, so it is what is read. Reading the
    /// old one would report a version nobody is working on.
    @Test func readsTheJSONFileWhenTheFolderHoldsBoth() throws {
        let url = try writeProject(named: "Both")

        let pbxproj = """
        // !$*UTF8*$!
        {
            archiveVersion = 1;
            objectVersion = 77;
            rootObject = ROOT;
            objects = {
                ROOT = {
                    isa = PBXProject;
                    knownRegions = (fr);
                    targets = (APP);
                };
                APP = {
                    isa = PBXNativeTarget;
                    name = Stale;
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
                        MARKETING_VERSION = 0.1;
                        SDKROOT = iphoneos;
                    };
                };
            };
        }
        """
        try Data(pbxproj.utf8).write(to: url.appending(path: "project.pbxproj"))

        let project = try XcodeProject.read(at: url)
        #expect(project.apps.first?.targetName == "Both")
        #expect(project.apps.first?.marketingVersion == "2.3")
        #expect(project.knownRegions == ["en", "de"])
    }

    // MARK: - Fixtures

    /// A project file with one app target, so a test can change one part of it
    /// and leave the rest alone.
    func projectFile(
        defaultConfiguration: String = "Release",
        localizations: String = #"  "localizations": { "development": "en" },"#,
        settings: String = "",
        projectSettings: String = ""
    ) -> String {
        """
        {
          "default-configuration": "\(defaultConfiguration)",
        \(localizations)
          "files": [
          ],
          "targets": [
            {
              "name": "Demo",
              "id": "0000000000000000000000D1",
              "product-type": "application",
              "build-settings": {
                \(settings)
              },
            },
          ],
          "build-settings": {
            \(projectSettings)
          },
        }
        """
    }
}
