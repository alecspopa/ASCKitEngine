import ASCKitAPI
import Foundation
import Testing
@testable import ASCKitProject

/// The table holds one device class per identifier App Store Connect takes,
/// for every platform the store lists an app on.
struct DeviceClassCatalogTests {
    @Test func namesOneDeviceClassPerAppStoreConnectIdentifier() {
        let displayTypes = DeviceClass.all.map(\.displayType)
        #expect(Set(displayTypes).count == displayTypes.count, "two classes would overwrite each other")
    }

    @Test func namesEveryDeviceClassOnce() {
        let ids = DeviceClass.all.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    /// A file name is read by trying the last three pieces, then two, then one,
    /// so an id of four pieces could never be read back.
    @Test func keepsEveryIdShortEnoughToReadOutOfAFileName() {
        for deviceClass in DeviceClass.all {
            let pieces = deviceClass.id.split(separator: "-").count
            #expect(pieces <= 3, "\(deviceClass.id) is \(pieces) pieces")
        }
    }

    /// The token goes to App Store Connect with the image and a later push
    /// matches on it, so it has to lead back to the device class it came from.
    @Test func readsEveryFileNameTokenBackAsTheDeviceClassItNames() {
        for deviceClass in DeviceClass.all {
            #expect(DeviceClass.named(deviceClass.fileNameToken.lowercased()) == deviceClass)
        }
    }

    @Test func writesEachPieceOfATokenTheWayAPersonWritesIt() {
        #expect(DeviceClass.iPhone69.fileNameToken == "iPhone-6.9")
        #expect(DeviceClass.mac.fileNameToken == "Mac")
        #expect(DeviceClass.watchSeries10.fileNameToken == "Watch-Series-10")
        #expect(DeviceClass.iMessageIPhone69.fileNameToken == "iMessage-iPhone-6.9")
    }

    @Test func namesADeviceTheWayAppleNamesIt() {
        #expect(DeviceClass.iPhone69.displayName == "iPhone 6.9 inch")
        #expect(DeviceClass.watchUltra.displayName == "Apple Watch Ultra")
        #expect(DeviceClass.mac.displayName == "Mac")
        #expect(DeviceClass.appleTV.displayName == "Apple TV")
    }

    @Test func takesTheSizesAppStoreConnectTakes() {
        #expect(DeviceClass.mac.accepts(width: 2880, height: 1800))
        #expect(DeviceClass.watchUltra.accepts(width: 410, height: 502))
        #expect(DeviceClass.appleTV.accepts(width: 3840, height: 2160))
        #expect(DeviceClass.mac.accepts(width: 1320, height: 2868) == false)
    }

    @Test(arguments: [
        (width: 422, height: 514), (width: 514, height: 422),
        (width: 410, height: 502), (width: 502, height: 410)
    ])
    func takesTheSizeOfEveryWatchUltraTheWayItIsHeldOrTurned(width: Int, height: Int) {
        #expect(DeviceClass.watchUltra.accepts(width: width, height: height))
    }

    @Test func leavesTheSeriesTenSizeOutOfTheUltraSlot() {
        #expect(DeviceClass.watchUltra.accepts(width: 416, height: 496) == false)
    }

    /// A Mac screenshot is wide, so the card that holds it is wide too.
    @Test func knowsAMacPictureIsWiderThanItIsTall() {
        #expect(DeviceClass.mac.aspectRatio > 1)
        #expect(DeviceClass.iPhone69.aspectRatio < 1)
    }

    /// Apple widened this slot to take the 6.3-inch sizes as well, and App
    /// Store Connect now labels it 6.3 inch.
    @Test func takesTheSixPointThreeInchSizesInTheSixPointOneInchSlot() {
        #expect(DeviceClass.iPhone61.accepts(width: 1206, height: 2622))
        #expect(DeviceClass.iPhone61.accepts(width: 1179, height: 2556))
        #expect(DeviceClass.iPhone61.accepts(width: 1170, height: 2532))
    }
}

/// A watch app and an iMessage app are both sold inside an iOS app, so both
/// belong to the iOS listing.
struct DeviceClassPlatformTests {
    @Test func putsEveryDeviceClassOnThePlatformThatSellsIt() {
        #expect(DeviceClass.mac.platform == .macOS)
        #expect(DeviceClass.appleTV.platform == .tvOS)
        #expect(DeviceClass.visionPro.platform == .visionOS)
        #expect(DeviceClass.watchUltra.platform == .ios)
        #expect(DeviceClass.iMessageIPhone69.platform == .ios)
    }

    @Test func givesAMacAppTheMacDeviceClassAndNoIPhoneOne() {
        let classes = DeviceClass.all(on: .macOS)
        #expect(classes == [.mac])
    }

    @Test func givesAniOSAppTheIPhoneTheIPadTheWatchAndTheIMessageOnes() {
        let families = Set(DeviceClass.all(on: .ios).map(\.heading))
        #expect(families == ["iPhone", "iPad", "Apple Watch", "iMessage App"])
    }

    @Test func startsANewProjectOnTheLargestSizeItsPlatformTakes() {
        #expect(DeviceClass.first(on: .ios) == .iPhone69)
        #expect(DeviceClass.first(on: .macOS) == .mac)
        #expect(DeviceClass.first(on: .tvOS) == .appleTV)
        #expect(DeviceClass.first(on: .visionOS) == .visionPro)
    }
}

/// App Store Connect puts a tab over each group. The page puts a heading over
/// each instead, so the whole page scrolls as one.
struct DeviceClassGroupingTests {
    @Test func gathersTheIMessageOnesUnderAHeadingOfTheirOwn() {
        let groups = DeviceClass.grouped(DeviceClass.all(on: .ios))
        let iMessage = groups.first { $0.heading == "iMessage App" }

        #expect(iMessage?.deviceClasses.contains(.iMessageIPhone69) == true)
        #expect(groups.first { $0.heading == "iPhone" }?.deviceClasses.contains(.iPhone69) == true)
    }

    @Test func keepsTheOrderTheTableHoldsThemIn() {
        let groups = DeviceClass.grouped(DeviceClass.all(on: .ios))
        #expect(groups.map(\.heading) == ["iPhone", "iPad", "Apple Watch", "iMessage App"])
    }

    @Test func leavesAnEmptyListEmpty() {
        #expect(DeviceClass.grouped([]).isEmpty)
    }
}

/// The screenshots page shows every slot App Store Connect takes, so an empty
/// one reads as empty rather than as missing.
struct ShownDeviceClassTests {
    func config(platform: String?, deviceClasses: [String]) -> ProjectConfig {
        ProjectConfig(
            bundleID: "com.example.app",
            keyID: "K",
            sourceLocale: "en-US",
            locales: ["en-US"],
            deviceClasses: deviceClasses,
            platform: platform
        )
    }

    @Test func showsTheMacSlotForAMacAppAndNoIPhoneOne() {
        let shown = config(platform: "macos", deviceClasses: []).shownDeviceClasses()
        #expect(shown == [.mac])
    }

    /// The list a person wrote is a decision, so a class from another platform
    /// stays on the page rather than disappearing off it.
    @Test func keepsAClassTheProjectListsFromAnotherPlatform() {
        let shown = config(platform: "macos", deviceClasses: ["iphone-6.9"]).shownDeviceClasses()
        #expect(shown.contains(.iPhone69))
        #expect(shown.contains(.mac))
    }

    /// The project's own platform is the stronger answer. A project that names
    /// none takes the one App Store Connect answered with.
    @Test func takesThePlatformTheStoreAnsweredWithWhenTheProjectNamesNone() {
        let shown = config(platform: nil, deviceClasses: []).shownDeviceClasses(fallbackPlatform: .macOS)
        #expect(shown == [.mac])
    }

    @Test func prefersThePlatformTheProjectNames() {
        let shown = config(platform: "macos", deviceClasses: []).shownDeviceClasses(fallbackPlatform: .ios)
        #expect(shown == [.mac])
    }

    /// Nothing has been read yet and the project names no platform, which is
    /// most apps and almost always iOS.
    @Test func fallsBackToIOSWithNothingToGoOn() {
        let shown = config(platform: nil, deviceClasses: []).shownDeviceClasses()
        #expect(shown.contains(.iPhone69))
        #expect(shown.contains(.mac) == false)
    }

    @Test func saysWhichOfThemTheProjectShips() {
        let config = config(platform: nil, deviceClasses: ["iphone-6.9"])
        #expect(config.ships(.iPhone69))
        #expect(config.ships(.iPad13) == false)
    }
}

/// Which platform an Xcode target builds for, which is what a new project
/// starts its screenshot sizes from.
final class XcodePlatformTests {
    let fixture: FixtureProject

    init() throws {
        fixture = try FixtureProject()
    }

    deinit {
        fixture.remove()
    }

    /// Writes an `.xcodeproj` whose release configuration holds these settings
    /// and nothing else worth reading.
    func app(settings: String) throws -> XcodeProject.App {
        let url = fixture.rootURL.appending(path: "Demo.xcodeproj")
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
                        \(settings)
                    };
                };
            };
        }
        """
        try pbxproj.write(
            to: url.appending(path: "project.pbxproj"), atomically: true, encoding: .utf8
        )
        let project = try XcodeProject.read(at: url)
        return try #require(project.apps.first)
    }

    @Test func readsThePlatformOutOfSDKROOT() throws {
        #expect(try app(settings: "SDKROOT = macosx;").platform == .macOS)
        #expect(try app(settings: "SDKROOT = iphoneos;").platform == .ios)
    }

    /// Xcode writes `auto` for most targets today, and `SUPPORTED_PLATFORMS`
    /// is then the setting that says which platforms the target has.
    @Test func readsTheSupportedPlatformsWhenSDKROOTSaysAuto() throws {
        let settings = """
        SDKROOT = auto;
        SUPPORTED_PLATFORMS = macosx;
        """
        #expect(try app(settings: settings).platform == .macOS)
    }

    /// A simulator SDK is the device SDK beside it, so naming both is still
    /// one platform.
    @Test func takesASimulatorSDKAsTheDeviceOneBesideIt() throws {
        let settings = """
        SDKROOT = auto;
        SUPPORTED_PLATFORMS = "iphoneos iphonesimulator";
        """
        #expect(try app(settings: settings).platform == .ios)
    }

    @Test func namesNoPlatformForATargetThatBuildsForSeveral() throws {
        let settings = """
        SDKROOT = auto;
        SUPPORTED_PLATFORMS = "iphoneos iphonesimulator macosx xros xrsimulator";
        """
        #expect(try app(settings: settings).platform == nil)
    }

    @Test func namesNoPlatformWhenNeitherSettingIsThere() throws {
        #expect(try app(settings: "MARKETING_VERSION = 1.0;").platform == nil)
    }
}

/// Taking a device class out of the list, which is what a row for a platform
/// the app is not sold on offers.
final class DroppingADeviceClassTests {
    let fixture: FixtureProject

    init() throws {
        fixture = try FixtureProject()
    }

    deinit {
        fixture.remove()
    }

    private func write(
        deviceClasses: [String],
        usesSourceScreenshots: [String: [String]] = [:],
        copiesScreenshotsFrom: [String: [String: String]] = [:]
    ) throws -> Project {
        try fixture.writeConfig(ProjectConfig(
            bundleID: "com.example.Demo",
            keyID: "ABC123",
            sourceLocale: "en-US",
            locales: ["en-US", "de-DE"],
            deviceClasses: deviceClasses,
            usesSourceScreenshots: usesSourceScreenshots,
            copiesScreenshotsFrom: copiesScreenshotsFrom
        ))
        return try fixture.load()
    }

    @Test func writesTheDeviceClassOutOfTheList() throws {
        let project = try write(deviceClasses: ["iphone-6.9", "mac"])
        let config = try DeviceClassAdoption.drop(.iPhone69, in: project)

        #expect(config.deviceClasses == ["mac"])
        #expect(try fixture.load().config.deviceClasses == ["mac"])
    }

    /// The settings are kept per device class, so the ones naming a class that
    /// has left name nothing.
    @Test func takesTheSettingsThatNamedItWithIt() throws {
        let project = try write(
            deviceClasses: ["iphone-6.9", "mac"],
            usesSourceScreenshots: ["de-DE": ["iphone-6.9"]],
            copiesScreenshotsFrom: ["es-ES": ["iphone-6.9": "es-MX"]]
        )
        let config = try DeviceClassAdoption.drop(.iPhone69, in: project)

        #expect(config.usesSourceScreenshots.isEmpty)
        #expect(config.copiesScreenshotsFrom.isEmpty)
    }

    @Test func leavesAListThatNeverNamedItAlone() throws {
        let project = try write(deviceClasses: ["mac"])
        let config = try DeviceClassAdoption.drop(.iPhone69, in: project)

        #expect(config.deviceClasses == ["mac"])
    }
}
