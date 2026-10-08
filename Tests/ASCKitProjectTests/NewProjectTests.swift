import Foundation
import Testing
@testable import ASCKitProject

/// What a new project would be, read out of a folder.
///
/// The app's sheet and `asckit init` both read it here, so a project made in
/// one is the project the other would have made.
final class NewProjectTests {
    let xcode: XcodeProjectTests

    init() throws {
        xcode = try XcodeProjectTests()
    }

    deinit {
        xcode.fixture.remove()
    }

    var folder: URL { xcode.fixture.rootURL }

    @Test func readsTheAppAndTheLanguagesOutOfTheXcodeProject() throws {
        try xcode.writeProject(knownRegions: ["de", "ja", "Base"])

        let found = try NewProject.read(in: folder)
        #expect(found.projectName == "Demo.xcodeproj")
        #expect(found.app.bundleID == "com.example.Demo")
        #expect(found.app.marketingVersion == "2.3")
        #expect(found.settledLocales == ["de-DE", "ja"])
        #expect(found.undecidedRegions.isEmpty)
        #expect(found.destination.lastPathComponent == ".asckit")
        #expect(found.alreadyAProject == false)
    }

    /// Xcode says `en` and the App Store has four. Nothing picks one, in either
    /// front end.
    @Test func leavesALanguageWithMoreThanOneAnswerUndecided() throws {
        try xcode.writeProject(knownRegions: ["en", "de"])

        let found = try NewProject.read(in: folder)
        #expect(found.settledLocales == ["de-DE"])

        let undecided = try #require(found.undecidedRegions.first)
        #expect(undecided.region == "en")
        #expect(undecided.choices == ["en-AU", "en-CA", "en-GB", "en-US"])
    }

    /// The app writes these, and the first one is the language the listing is
    /// written in. `de` gives one App Store locale straight away and `en` waits
    /// for an answer, so taking the settled ones first would write a German
    /// listing for an app written in English.
    @Test func keepsTheXcodeOrderSoTheDevelopmentLanguageLeadsTheList() throws {
        try xcode.writeProject(knownRegions: ["en", "de"], developmentRegion: "en")

        let found = try NewProject.read(in: folder)
        #expect(found.locales(choosing: ["en": "en-US"]) == ["en-US", "de-DE"])
    }

    /// A region nobody answered for is left out, the same as one the App Store
    /// has no locale for.
    @Test func leavesOutARegionWithNoAnswer() throws {
        try xcode.writeProject(knownRegions: ["en", "de", "cy"])

        let found = try NewProject.read(in: folder)
        #expect(found.locales() == ["de-DE"])
        #expect(found.locales(choosing: ["en": ""]) == ["de-DE"])
    }

    @Test func refusesAFolderWithNoXcodeProject() throws {
        #expect(throws: ProjectError.self) {
            try NewProject.read(in: folder)
        }
    }

    /// Scaffolding for the wrong target writes a listing that pushes to another
    /// app's page, so a project building two is refused rather than guessed at.
    @Test func refusesAProjectBuildingMoreThanOneAppUntilToldWhich() throws {
        try writeTwoAppProject()

        #expect(throws: NewProjectError.self) {
            try NewProject.read(in: folder)
        }
        #expect(try NewProject.read(in: folder, target: "Second").app.targetName == "Second")
    }

    @Test func refusesATargetTheProjectDoesNotBuild() throws {
        try xcode.writeProject()

        #expect(throws: NewProjectError.self) {
            try NewProject.read(in: folder, target: "Nothing")
        }
    }

    /// Writing over a project would take its key identifiers with it, so both
    /// front ends are told before they offer to write anything.
    @Test func saysWhenThereIsAProjectThereAlready() throws {
        try xcode.writeProject()
        try ProjectScaffold.create(
            in: folder,
            config: ProjectConfig(
                bundleID: "com.example.Demo",
                keyID: "ABC123",
                issuerID: nil,
                sourceLocale: "en-US",
                locales: ["en-US"],
                deviceClasses: [DeviceClass.iPhone69.id]
            ),
            version: "1.0"
        )

        #expect(try NewProject.read(in: folder).alreadyAProject)
    }

    /// Two application targets in one project, which is what an app with a
    /// second flavour of itself looks like. Written here rather than through
    /// the shared fixture, which lists one app and its tests.
    func writeTwoAppProject() throws {
        let url = folder.appending(path: "Demo.xcodeproj")
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
                    knownRegions = (
                        en,
                    );
                    targets = (APP, SECOND);
                };
                APP = {
                    isa = PBXNativeTarget;
                    name = Demo;
                    productType = "com.apple.product-type.application";
                    buildConfigurationList = APPLIST;
                };
                SECOND = {
                    isa = PBXNativeTarget;
                    name = Second;
                    productType = "com.apple.product-type.application";
                    buildConfigurationList = APPLIST;
                };
                APPLIST = {
                    isa = XCConfigurationList;
                    defaultConfigurationName = Release;
                    buildConfigurations = (RELEASE);
                };
                RELEASE = {
                    isa = XCBuildConfiguration;
                    name = Release;
                    buildSettings = {
                        PRODUCT_BUNDLE_IDENTIFIER = "com.example.Demo";
                        MARKETING_VERSION = 2.3;
                        SDKROOT = iphoneos;
                    };
                };
            };
        }
        """
        try Data(pbxproj.utf8).write(to: url.appending(path: "project.pbxproj"))
    }
}
