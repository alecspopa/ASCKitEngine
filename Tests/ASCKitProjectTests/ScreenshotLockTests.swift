import ASCKitAPI
import Foundation
import Testing
@testable import ASCKitProject

/// A released version takes no new screenshot, so nothing may be filed into
/// its folder. The window, the terminal and the MCP tools all ask this rule.
final class ScreenshotLockTests {
    let fixture: FixtureProject

    init() throws {
        fixture = try FixtureProject()
        try fixture.writeConfig(ProjectConfig(
            bundleID: "com.example.Demo",
            keyID: "ABC123",
            issuerID: "issuer",
            sourceLocale: "en-US",
            locales: ["en-US"],
            deviceClasses: [DeviceClass.iPhone69.id]
        ))
    }

    deinit {
        fixture.remove()
    }

    static func listing(
        version: String,
        state: AppVersionState?,
        released: String? = nil
    ) -> RemoteListing {
        RemoteListing(
            appID: "app1",
            appName: "Demo",
            bundleID: "com.example.Demo",
            appInfoID: nil,
            appInfoState: nil,
            versionID: "v1",
            versionString: version,
            versionState: state,
            releasedVersionString: released,
            appInfoLocalizations: [:],
            versionLocalizations: [:],
            screenshotSets: []
        )
    }

    // MARK: - The rule

    @Test(arguments: [AppVersionState.readyForDistribution, .waitingForReview, .inReview])
    func locksTheVersionAppStoreConnectIsOnWhenItTakesNoScreenshots(_ state: AppVersionState) {
        let lock = ScreenshotLock.lock(version: "1.1", listing: Self.listing(version: "1.1", state: state))
        #expect(lock == ScreenshotLock(version: "1.1", state: state.rawValue, storeVersion: "1.1"))
    }

    @Test(arguments: [AppVersionState.prepareForSubmission, .rejected, .developerRejected])
    func leavesAVersionThatTakesScreenshots(_ state: AppVersionState) {
        #expect(ScreenshotLock.lock(version: "1.1", listing: Self.listing(version: "1.1", state: state)) == nil)
    }

    /// App Store Connect moved on to 1.2 and there is no folder for it yet, so
    /// the newest folder is the one on sale.
    @Test func locksTheReleasedFolderWhenAppStoreConnectMovedOn() {
        let listing = Self.listing(version: "1.2", state: .prepareForSubmission, released: "1.1")
        let lock = ScreenshotLock.lock(version: "1.1", listing: listing)

        #expect(lock?.storeVersion == "1.2")
        #expect(lock?.description.contains("Make the folder for version 1.2 first.") == true)
    }

    /// A folder for the next version, made before App Store Connect has it.
    @Test func leavesAFolderNewerThanAppStoreConnect() {
        let listing = Self.listing(version: "1.1", state: .readyForDistribution, released: "1.1")
        #expect(ScreenshotLock.lock(version: "1.2", listing: listing) == nil)
    }

    @Test func leavesEverythingWithNoListing() {
        #expect(ScreenshotLock.lock(version: "1.1", listing: nil) == nil)
    }

    @Test func namesTheVersionAndTheState() {
        let lock = ScreenshotLock(version: "1.1", state: "READY_FOR_DISTRIBUTION", storeVersion: "1.1")
        #expect(lock.description == """
        Version 1.1 is READY_FOR_DISTRIBUTION and does not accept screenshots. \
        Add a new version in App Store Connect first.
        """)
    }

    // MARK: - Filing

    @Test func filesNothingIntoALockedVersion() throws {
        let project = try fixture.load()
        let folder = project.rootURL.appending(path: ProjectScaffold.inboxName)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let image = folder.appending(path: "01-hero-iPhone-6.9-en_US.png")
        try PNGWriter.write(to: image, width: 1290, height: 2796, hasAlpha: false, seed: "hero")

        let listing = Self.listing(version: "1.0", state: .readyForDistribution)
        #expect(throws: ScreenshotLock.self) {
            try Inbox.file(Inbox.plan(in: project), version: "1.0", listing: listing, in: project)
        }

        #expect(FileManager.default.fileExists(atPath: image.path))
        let slot = fixture.screenshotsDirectory(locale: "en-US", deviceClassID: DeviceClass.iPhone69.id)
        let filed = (try? FileManager.default.contentsOfDirectory(atPath: slot.path)) ?? []
        #expect(filed.filter { $0.hasPrefix(".") == false }.isEmpty)
    }
}
