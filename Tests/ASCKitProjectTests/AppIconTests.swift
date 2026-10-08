import Foundation
import Testing
@testable import ASCKitProject

/// Finding the app's own icon in the repository beside the listing.
final class AppIconTests {
    let fixture: FixtureProject

    init() throws {
        fixture = try FixtureProject()
    }

    deinit {
        fixture.remove()
    }

    /// An icon set with the same artwork at several sizes, which is what Xcode
    /// writes.
    @discardableResult
    func writeIconSet(
        named name: String = "AppIcon",
        under path: String = "Demo/Assets.xcassets",
        sizes: [Int] = [64, 1024, 128]
    ) throws -> URL {
        let folder = fixture.rootURL
            .appending(path: path)
            .appending(path: "\(name).appiconset")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        for size in sizes {
            try PNGWriter.write(
                to: folder.appending(path: "icon-\(size).png"),
                width: size,
                height: size,
                hasAlpha: false,
                seed: "icon-\(size)"
            )
        }
        return folder
    }

    /// An Icon Composer document. The layers are what it really holds, and
    /// nothing here reads them: what matters is that the folder is found and
    /// not walked into.
    @discardableResult
    func writeIconComposerDocument(
        named name: String = "AppIcon",
        under path: String = "Demo"
    ) throws -> URL {
        let folder = fixture.rootURL
            .appending(path: path)
            .appending(path: "\(name).icon")
        try FileManager.default.createDirectory(
            at: folder.appending(path: "Assets"),
            withIntermediateDirectories: true
        )
        try Data(#"{"groups":[]}"#.utf8).write(to: folder.appending(path: "icon.json"))
        return folder
    }

    // MARK: - An icon set

    /// An icon set holds the same artwork at every size a device asks for, so
    /// the biggest is the only one worth showing.
    @Test func picksTheLargestImageInTheSet() throws {
        try writeIconSet()

        let found = try #require(AppIcon.find(in: fixture.rootURL))
        #expect(found.imageURL?.lastPathComponent == "icon-1024.png")
        #expect(found.iconComposerURL == nil)
    }

    @Test func findsTheSetTheTargetNames() throws {
        try writeIconSet(named: "MarketingIcon", sizes: [256])

        #expect(AppIcon.find(in: fixture.rootURL, named: "MarketingIcon") != nil)
        #expect(AppIcon.find(in: fixture.rootURL) == nil)
    }

    @Test func findsNothingInAFolderWithNoIcon() {
        #expect(AppIcon.find(in: fixture.rootURL) == nil)
    }

    /// An icon set with nothing in it is a folder, not a picture.
    @Test func findsNothingInAnEmptySet() throws {
        try writeIconSet(sizes: [])

        #expect(AppIcon.find(in: fixture.rootURL) == nil)
    }

    // MARK: - An Icon Composer document

    @Test func findsTheIconComposerDocument() throws {
        let document = try writeIconComposerDocument()

        let found = try #require(AppIcon.find(in: fixture.rootURL))
        #expect(found.iconComposerURL == document)
        #expect(found.imageURL == nil)
    }

    /// A project moving to Icon Composer keeps its icon set for older releases.
    /// Both are carried, because only one of them can be drawn without Xcode.
    @Test func findsBothWhenTheProjectKeepsBoth() throws {
        try writeIconComposerDocument()
        try writeIconSet(sizes: [1024])

        let found = try #require(AppIcon.find(in: fixture.rootURL))
        #expect(found.iconComposerURL?.lastPathComponent == "AppIcon.icon")
        #expect(found.imageURL?.lastPathComponent == "icon-1024.png")
    }

    /// A `.icon` is one icon rather than a place icons are kept, so the walk
    /// stops at it. An `.appiconset` inside one is not a second answer.
    @Test func doesNotLookInsideAnIconComposerDocument() throws {
        try writeIconComposerDocument(named: "Other", under: "Demo")
        try writeIconSet(under: "Demo/Other.icon", sizes: [512])

        #expect(AppIcon.find(in: fixture.rootURL) == nil)
    }

    // MARK: - Where it looks

    /// A repository with a sample app inside it should show its own icon rather
    /// than the sample's, so the shallow one wins.
    @Test func prefersTheIconNearestTheTopOfTheRepository() throws {
        try writeIconSet(under: "Examples/Sample/Assets.xcassets", sizes: [512])
        try writeIconSet(under: "Assets.xcassets", sizes: [256])

        let found = try #require(AppIcon.find(in: fixture.rootURL))
        #expect(found.imageURL?.path.contains("Examples") == false)
    }

    /// Anything under `.build` is something that was built rather than
    /// something somebody drew, and walking it costs more than it is worth.
    @Test func doesNotLookInsideBuildFolders() throws {
        try writeIconSet(under: ".build/checkouts/Other/Assets.xcassets", sizes: [512])

        #expect(AppIcon.find(in: fixture.rootURL) == nil)
    }

    // MARK: - Through the Xcode project

    @Test func readsTheIconNameOutOfTheXcodeProject() throws {
        try FileManager.default.createDirectory(
            at: fixture.rootURL.appending(path: "Demo.xcodeproj"),
            withIntermediateDirectories: true
        )
        try Data(Self.pbxproj.utf8).write(
            to: fixture.rootURL.appending(path: "Demo.xcodeproj/project.pbxproj")
        )
        try writeIconSet(named: "BrandIcon", sizes: [180])

        let found = try #require(
            AppIcon.find(in: fixture.rootURL, forBundleID: "com.example.Demo")
        )
        #expect(found.imageURL?.lastPathComponent == "icon-180.png")
    }

    static let pbxproj = """
    // !$*UTF8*$!
    {
        archiveVersion = 1;
        objectVersion = 77;
        rootObject = ROOT;
        objects = {
            ROOT = {
                isa = PBXProject;
                knownRegions = (en,);
                targets = (APP);
            };
            APP = {
                isa = PBXNativeTarget;
                name = Demo;
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
                    ASSETCATALOG_COMPILER_APPICON_NAME = BrandIcon;
                    SDKROOT = iphoneos;
                };
            };
        };
    }
    """
}
