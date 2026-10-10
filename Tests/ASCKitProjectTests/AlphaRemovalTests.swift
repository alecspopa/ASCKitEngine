import Foundation
import ImageIO
import Testing
@testable import ASCKitProject

/// A screenshot with an alpha channel is a file App Store Connect refuses and a
/// picture nothing is wrong with. Clearing the channel is the whole fix, so the
/// inbox offers it rather than asking for another export.
final class AlphaRemovalTests {
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

    @discardableResult
    private func putInInbox(
        named fileName: String,
        width: Int = 1320,
        height: Int = 2868,
        hasAlpha: Bool = true
    ) throws -> URL {
        let folder = try fixture.load().rootURL.appending(path: ProjectScaffold.inboxName)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let url = folder.appending(path: fileName)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try PNGWriter.write(
            to: url, width: width, height: height, hasAlpha: hasAlpha, seed: fileName
        )
        return url
    }

    private func plan() throws -> Inbox.Plan {
        try Inbox.plan(in: fixture.load())
    }

    // MARK: - What the refusal carries

    /// One line, because the band under the list offers the way out and a
    /// refusal that said it too would say it twice.
    @Test func saysTheChannelAndStops() throws {
        try putInInbox(named: "01-overview-iPhone-6.9-en_US.png")

        let refusal = try #require(try plan().refusals.first)
        #expect(refusal.reason == "01-overview-iPhone-6.9-en_US.png has an alpha channel.")
    }

    /// A file of the wrong size keeps the reason that names the sizes. Clearing
    /// it would change the picture and leave it refused.
    @Test func keepsTheWholeReasonForARefusalNothingHereCanAnswer() throws {
        try putInInbox(named: "01-overview-iPhone-6.9-en_US.png", width: 800, height: 600)

        let refusal = try #require(try plan().refusals.first)
        #expect(refusal.reason.contains("800x600"))
    }

    @Test func namesTheWaitingFilesAnAlphaChannelAloneKeepsOut() throws {
        try putInInbox(named: "01-overview-iPhone-6.9-en_US.png")
        try putInInbox(named: "02-budgets-iPhone-6.9-en_US.png", hasAlpha: false)

        let waiting = try AlphaRemoval.clearable(in: plan())
        #expect(waiting.map(\.fileName) == ["01-overview-iPhone-6.9-en_US.png"])
    }

    /// Clearing the channel would leave the file refused, so it is not offered.
    /// The picture is the wrong size, and no rewrite of it changes that.
    @Test func leavesAFileTheDeviceClassWouldRefuseAnyway() throws {
        try putInInbox(named: "01-overview-iPhone-6.9-en_US.png", width: 800, height: 600)

        let refusals = try plan().refusals
        #expect(refusals.count == 1)
        #expect(refusals.first?.hasClearableAlpha == false)
        #expect(try AlphaRemoval.clearable(in: plan()).isEmpty)
    }

    /// A name nobody can read says nothing about which device class would take
    /// the image, so nothing here knows whether clearing it would help.
    @Test func leavesAFileWhoseNameSaysNothing() throws {
        try putInInbox(named: "screenshot.png")

        #expect(try AlphaRemoval.clearable(in: plan()).isEmpty)
    }

    /// A treatment and a custom page wait in the same inbox, so the same clear
    /// is offered there and a channel is not a dead end.
    @Test func offersTheClearForAProductPageOptimizationImage() throws {
        let url = try putInInbox(named: "product-page-optimization/test/blue/01-overview-iPhone-6.9-en_US.png")
        let project = try fixture.load()
        try FileManager.default.createDirectory(
            at: project.experimentURL(experiment: "test", treatment: "blue"), withIntermediateDirectories: true
        )

        let plan = Inbox.plan(in: project)
        #expect(plan.refusals.first?.reason == "01-overview-iPhone-6.9-en_US.png has an alpha channel.")
        #expect(AlphaRemoval.clearable(in: plan).map(\.url) == [url])
    }

    @Test func offersTheClearForACustomPageImage() throws {
        let url = try putInInbox(named: "custom-product-pages/spring/01-overview-iPhone-6.9-en_US.png")
        let project = try fixture.load()
        try FileManager.default.createDirectory(
            at: project.customPageURL(page: "spring"), withIntermediateDirectories: true
        )

        let plan = Inbox.plan(in: project)
        #expect(AlphaRemoval.clearable(in: plan).map(\.url) == [url])
    }

    // MARK: - Clearing it

    @Test func writesTheImageAgainWithNoAlphaChannel() throws {
        let url = try putInInbox(named: "01-overview-iPhone-6.9-en_US.png")

        let outcome = AlphaRemoval.clear([url])
        #expect(outcome.cleared == ["01-overview-iPhone-6.9-en_US.png"])
        #expect(outcome.failed.isEmpty)

        let file = ImageInspector.inspect(url: url)
        #expect(file.hasAlpha == false)
        #expect(file.pixelWidth == 1320)
        #expect(file.pixelHeight == 2868)
    }

    /// The pixels change, so the file somebody dropped in is kept rather than
    /// written over and gone.
    @Test func putsTheFileAsItArrivedInTheTrash() throws {
        let url = try putInInbox(named: "01-overview-iPhone-6.9-en_US.png")

        let outcome = AlphaRemoval.clear([url])
        let trashed = try #require(outcome.trashed.first)
        #expect(FileManager.default.fileExists(atPath: trashed.path))
        #expect(ImageInspector.inspect(url: trashed).hasAlpha == true)

        try? FileManager.default.removeItem(at: trashed)
    }

    @Test func filesTheClearedImageAsItIs() throws {
        let url = try putInInbox(named: "01-overview-iPhone-6.9-en_US.png")
        #expect(try plan().arrivals.isEmpty)

        let outcome = AlphaRemoval.clear([url])
        let arrivals = try plan().arrivals
        #expect(arrivals.map(\.file.fileName) == ["01-overview-iPhone-6.9-en_US.png"])
        #expect(try plan().refusals.isEmpty)

        for trashed in outcome.trashed {
            try? FileManager.default.removeItem(at: trashed)
        }
    }

    /// One file nobody can read does not stop the rest, because a person who
    /// pressed the button once should not have to press it file by file.
    @Test func clearsTheRestWhenOneFileCannotBeRead() throws {
        let good = try putInInbox(named: "01-overview-iPhone-6.9-en_US.png")
        let bad = try fixture.load().rootURL
            .appending(path: ProjectScaffold.inboxName)
            .appending(path: "broken.png")
        try Data("not an image".utf8).write(to: bad)

        let outcome = AlphaRemoval.clear([bad, good])
        #expect(outcome.cleared == ["01-overview-iPhone-6.9-en_US.png"])
        #expect(outcome.failed.map(\.fileName) == ["broken.png"])
        #expect(ImageInspector.inspect(url: good).hasAlpha == false)

        for trashed in outcome.trashed {
            try? FileManager.default.removeItem(at: trashed)
        }
    }

    @Test func saysWhatItDid() throws {
        let url = try putInInbox(named: "01-overview-iPhone-6.9-en_US.png")

        let outcome = AlphaRemoval.clear([url])
        let text = PushOutcomeText.describe(outcome)
        #expect(text.contains("01-overview-iPhone-6.9-en_US.png"))
        #expect(text.contains("Trash"))

        for trashed in outcome.trashed {
            try? FileManager.default.removeItem(at: trashed)
        }
    }
}
