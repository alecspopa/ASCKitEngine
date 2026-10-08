import Foundation
import Testing
@testable import ASCKitProject

/// An app that starts shipping on a device it did not ship on before has the
/// screenshots before it has the line in `asckit.json`. What is waiting in the
/// inbox is what says which device class that is, so the images are the answer
/// rather than the problem.
final class DeviceClassAdoptionTests {
    let fixture: FixtureProject

    init() throws {
        fixture = try FixtureProject()
        try fixture.writeConfig(ProjectConfig(
            bundleID: "com.example.Demo",
            keyID: "ABC123",
            issuerID: "issuer",
            sourceLocale: "en-US",
            locales: ["en-US", "de-DE"],
            deviceClasses: [DeviceClass.iPhone69.id]
        ))
    }

    deinit {
        fixture.remove()
    }

    @discardableResult
    private func putInInbox(named fileName: String, width: Int, height: Int) throws -> URL {
        let folder = try fixture.load().rootURL.appending(path: ProjectScaffold.inboxName)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let url = folder.appending(path: fileName)
        try PNGWriter.write(to: url, width: width, height: height, hasAlpha: false, seed: fileName)
        return url
    }

    private func putIPadImage(named fileName: String) throws {
        try putInInbox(named: fileName, width: 2064, height: 2752)
    }

    private func folderExists(locale: String, deviceClassID: String) throws -> Bool {
        let url = try fixture.load().screenshotsURL(
            version: fixture.version, locale: locale, deviceClassID: deviceClassID
        )
        return FileManager.default.fileExists(atPath: url.path)
    }

    // MARK: - What the refusal carries

    @Test func namesTheDeviceClassTheWaitingImagesAskFor() throws {
        try putIPadImage(named: "01-overview-iPad-13-en_US.png")
        try putIPadImage(named: "02-budgets-iPad-13-en_US.png")

        let plan = try Inbox.plan(in: fixture.load())
        #expect(DeviceClassAdoption.unlisted(in: plan) == [.iPad13])
        #expect(DeviceClassAdoption.waitingCount(for: [.iPad13], in: plan) == 2)
    }

    /// A name nobody can read says nothing about a device class, so there is
    /// nothing here to offer and renaming is the only way out.
    @Test func offersNothingForAFileNamedWrong() throws {
        try putInInbox(named: "screenshot.png", width: 2064, height: 2752)

        let plan = try Inbox.plan(in: fixture.load())
        #expect(plan.hasInvalidNames)
        #expect(DeviceClassAdoption.unlisted(in: plan).isEmpty)
    }

    /// The device class is listed and the image is the wrong size. Listing it
    /// again would change nothing, so nothing is offered.
    @Test func offersNothingWhenTheImageItselfIsRefused() throws {
        try putInInbox(named: "01-small-iPhone-6.9-en_US.png", width: 800, height: 600)

        let plan = try Inbox.plan(in: fixture.load())
        #expect(plan.refusals.count == 1)
        #expect(DeviceClassAdoption.unlisted(in: plan).isEmpty)
    }

    // MARK: - Taking it in

    @Test func addsTheDeviceClassToTheListAndKeepsTheOneAlreadyThere() throws {
        let project = try fixture.load()
        let outcome = try DeviceClassAdoption.adopt(
            [.iPad13], version: fixture.version, in: project
        )

        #expect(outcome.added == [DeviceClass.iPad13.id])
        #expect(outcome.config.deviceClasses == [DeviceClass.iPhone69.id, DeviceClass.iPad13.id])
        #expect(try fixture.load().config.deviceClasses
            == [DeviceClass.iPhone69.id, DeviceClass.iPad13.id])
    }

    @Test func makesTheScreenshotFolderForEveryLanguage() throws {
        try DeviceClassAdoption.adopt([.iPad13], version: fixture.version, in: fixture.load())

        #expect(try folderExists(locale: "en-US", deviceClassID: DeviceClass.iPad13.id))
        #expect(try folderExists(locale: "de-DE", deviceClassID: DeviceClass.iPad13.id))
    }

    /// A project with no version folder has nowhere to make the folders, and
    /// the list is still worth writing.
    @Test func writesTheListWithNoVersionFolder() throws {
        let outcome = try DeviceClassAdoption.adopt([.iPad13], version: nil, in: fixture.load())

        #expect(outcome.added == [DeviceClass.iPad13.id])
        #expect(try fixture.load().config.deviceClasses.contains(DeviceClass.iPad13.id))
    }

    @Test func writesNothingForADeviceClassAlreadyListed() throws {
        let outcome = try DeviceClassAdoption.adopt(
            [.iPhone69], version: fixture.version, in: fixture.load()
        )

        #expect(outcome.added.isEmpty)
        #expect(outcome.left == [DeviceClass.iPhone69.id])
        #expect(try fixture.load().config.deviceClasses == [DeviceClass.iPhone69.id])
    }

    // MARK: - What it unblocks

    @Test func filesTheWaitingImagesOnceTheDeviceClassIsListed() throws {
        try putIPadImage(named: "01-overview-iPad-13-en_US.png")
        try putIPadImage(named: "02-budgets-iPad-13-en_US.png")

        let before = try Inbox.plan(in: fixture.load())
        #expect(before.arrivals.isEmpty)

        try DeviceClassAdoption.adopt(
            DeviceClassAdoption.unlisted(in: before), version: fixture.version, in: fixture.load()
        )

        let project = try fixture.load()
        let after = Inbox.plan(in: project)
        #expect(after.refusals.isEmpty)
        #expect(after.arrivals.count == 2)

        let outcome = try Inbox.file(after, version: fixture.version, in: project)
        defer {
            for url in outcome.trashed {
                try? FileManager.default.removeItem(at: url)
            }
        }

        let directory = fixture.screenshotsDirectory(
            locale: "en-US", deviceClassID: DeviceClass.iPad13.id
        )
        let filed = try FileManager.default
            .contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasPrefix(".") == false }
            .sorted()
        #expect(filed == ["01-overview-iPad-13-en_US.png", "02-budgets-iPad-13-en_US.png"])
    }
}
