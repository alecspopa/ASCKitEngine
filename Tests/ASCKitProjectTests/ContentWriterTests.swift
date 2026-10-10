import Foundation
import Testing
@testable import ASCKitProject

/// The writer is what a machine drives, so a refusal has to happen before
/// anything moves rather than after.
final class ContentWriterTests {
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

    /// A folder outside the project, standing in for `inbox`.
    func makeIncoming() throws -> URL {
        let url = fixture.rootURL.appending(path: "incoming-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @discardableResult
    func makeImage(
        in folder: URL,
        named fileName: String,
        width: Int = 1290,
        height: Int = 2796,
        hasAlpha: Bool = false
    ) throws -> URL {
        let url = folder.appending(path: fileName)
        try PNGWriter.write(to: url, width: width, height: height, hasAlpha: hasAlpha, seed: fileName)
        return url
    }

    func slot() throws -> [String] {
        let directory = fixture.screenshotsDirectory(locale: "en-US", deviceClassID: DeviceClass.iPhone69.id)
        return try FileManager.default
            .contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasPrefix(".") == false }
            .sorted { $0.compare($1, options: .numeric) == .orderedAscending }
    }

    // MARK: - App information

    @Test func writesALanguageTheCheckerCanRead() throws {
        let information = AppInformation(
            locale: "de-DE",
            status: .aiApproved,
            fields: AppInformation.Fields(name: "Beispiel")
        )
        try ContentWriter.writeAppInformation(information, version: "1.0", in: fixture.load())

        let read = try fixture.content().appInformation["de-DE"]
        #expect(read?.fields.name == "Beispiel")
        #expect(read?.status == .aiApproved)
    }

    @Test func makesTheFolderForALanguageThatIsTheFirstOne() throws {
        let fresh = try FixtureProject()
        defer { fresh.remove() }
        try fresh.writeConfig(ProjectConfig(
            bundleID: "com.example.Demo",
            keyID: "ABC123",
            issuerID: "issuer",
            sourceLocale: "en-US",
            locales: ["en-US"],
            deviceClasses: [DeviceClass.iPhone69.id]
        ))

        try ContentWriter.writeAppInformation(
            AppInformation(locale: "en-US", status: .draft),
            version: "1.0",
            in: fresh.load()
        )

        #expect(try fresh.content().appInformation["en-US"] != nil)
    }

    // MARK: - Adding screenshots

    @Test func numbersImagesAsTheyArrive() throws {
        let incoming = try makeIncoming()
        try makeImage(in: incoming, named: "hero.png")
        try makeImage(in: incoming, named: "shared.png")

        try ContentWriter.addScreenshots(
            from: [incoming.appending(path: "hero.png"), incoming.appending(path: "shared.png")],
            locale: "en-US",
            deviceClass: .iPhone69,
            at: .version("1.0"),
            in: fixture.load()
        )

        #expect(try slot() == ["01-hero-iPhone-6.9-en_US.png", "02-shared-iPhone-6.9-en_US.png"])
    }

    @Test func keepsTheSlugAndDropsTheOldNumber() throws {
        let incoming = try makeIncoming()
        try makeImage(in: incoming, named: "07-running-low.png")

        try ContentWriter.addScreenshots(
            from: [incoming.appending(path: "07-running-low.png")],
            locale: "en-US",
            deviceClass: .iPhone69,
            at: .version("1.0"),
            in: fixture.load()
        )

        #expect(try slot() == ["01-running-low-iPhone-6.9-en_US.png"])
    }

    /// A file already named under the rule keeps that name, and only its
    /// number moves.
    @Test func keepsTheDeviceAndTheLanguageTheNameCameWith() throws {
        let incoming = try makeIncoming()
        try makeImage(in: incoming, named: "03-shopping-iPhone-6.9-en_US.png")

        try ContentWriter.addScreenshots(
            from: [incoming.appending(path: "03-shopping-iPhone-6.9-en_US.png")],
            locale: "en-US",
            deviceClass: .iPhone69,
            at: .version("1.0"),
            in: fixture.load()
        )

        #expect(try slot() == ["01-shopping-iPhone-6.9-en_US.png"])
    }

    @Test func putsAnImageWhereItWasAskedAndPushesTheRestDown() throws {
        try fixture.writeScreenshot(
            locale: "en-US", deviceClassID: DeviceClass.iPhone69.id,
            named: "01-hero.png", width: 1290, height: 2796
        )
        try fixture.writeScreenshot(
            locale: "en-US", deviceClassID: DeviceClass.iPhone69.id,
            named: "02-shared.png", width: 1290, height: 2796
        )

        let incoming = try makeIncoming()
        try makeImage(in: incoming, named: "widgets.png")

        try ContentWriter.addScreenshots(
            from: [incoming.appending(path: "widgets.png")],
            locale: "en-US",
            deviceClass: .iPhone69,
            at: .version("1.0"),
            position: 1,
            in: fixture.load()
        )

        #expect(try slot() == [
            "01-widgets-iPhone-6.9-en_US.png",
            "02-hero-iPhone-6.9-en_US.png",
            "03-shared-iPhone-6.9-en_US.png"
        ])
    }

    @Test func addsToTheEndWhenNoPositionIsGiven() throws {
        try fixture.writeScreenshot(
            locale: "en-US", deviceClassID: DeviceClass.iPhone69.id,
            named: "01-hero.png", width: 1290, height: 2796
        )

        let incoming = try makeIncoming()
        try makeImage(in: incoming, named: "shared.png")

        try ContentWriter.addScreenshots(
            from: [incoming.appending(path: "shared.png")],
            locale: "en-US",
            deviceClass: .iPhone69,
            at: .version("1.0"),
            in: fixture.load()
        )

        #expect(try slot() == ["01-hero-iPhone-6.9-en_US.png", "02-shared-iPhone-6.9-en_US.png"])
    }

    // MARK: - Refusing an image

    @Test func refusesAnImageOfTheWrongSizeAndSaysWhichSizesFit() throws {
        let incoming = try makeIncoming()
        try makeImage(in: incoming, named: "small.png", width: 800, height: 600)

        #expect(throws: ContentWriteError.self) {
            try ContentWriter.addScreenshots(
                from: [incoming.appending(path: "small.png")],
                locale: "en-US",
                deviceClass: .iPhone69,
                at: .version("1.0"),
                in: self.fixture.load()
            )
        }
    }

    @Test func refusesAnImageWithAnAlphaChannel() throws {
        let incoming = try makeIncoming()
        try makeImage(in: incoming, named: "clear.png", hasAlpha: true)

        let error = #expect(throws: ContentWriteError.self) {
            try ContentWriter.addScreenshots(
                from: [incoming.appending(path: "clear.png")],
                locale: "en-US",
                deviceClass: .iPhone69,
                at: .version("1.0"),
                in: self.fixture.load()
            )
        }
        #expect("\(error!)".contains("alpha channel"))
    }

    /// One bad file in a batch has to leave the slot exactly as it was.
    /// A half-written set is worse than a refused one.
    @Test func writesNothingWhenOneImageInTheBatchIsRefused() throws {
        try fixture.writeScreenshot(
            locale: "en-US", deviceClassID: DeviceClass.iPhone69.id,
            named: "01-hero.png", width: 1290, height: 2796
        )

        let incoming = try makeIncoming()
        try makeImage(in: incoming, named: "good.png")
        try makeImage(in: incoming, named: "bad.png", width: 100, height: 100)

        #expect(throws: ContentWriteError.self) {
            try ContentWriter.addScreenshots(
                from: [incoming.appending(path: "good.png"), incoming.appending(path: "bad.png")],
                locale: "en-US",
                deviceClass: .iPhone69,
                at: .version("1.0"),
                in: self.fixture.load()
            )
        }

        #expect(try slot() == ["01-hero.png"])
    }

    @Test func refusesAnEleventhScreenshot() throws {
        for number in 1 ... 10 {
            try fixture.writeScreenshot(
                locale: "en-US", deviceClassID: DeviceClass.iPhone69.id,
                named: String(format: "%02d-shot.png", number), width: 1290, height: 2796
            )
        }

        let incoming = try makeIncoming()
        try makeImage(in: incoming, named: "one-more.png")

        let error = #expect(throws: ContentWriteError.self) {
            try ContentWriter.addScreenshots(
                from: [incoming.appending(path: "one-more.png")],
                locale: "en-US",
                deviceClass: .iPhone69,
                at: .version("1.0"),
                in: self.fixture.load()
            )
        }
        #expect("\(error!)".contains("limit of 10"))
    }

    @Test func refusesAFileThatIsNotThere() throws {
        let incoming = try makeIncoming()

        #expect(throws: ContentWriteError.self) {
            try ContentWriter.addScreenshots(
                from: [incoming.appending(path: "nothing.png")],
                locale: "en-US",
                deviceClass: .iPhone69,
                at: .version("1.0"),
                in: self.fixture.load()
            )
        }
    }

    // MARK: - Reordering

    @Test func putsASlotInTheOrderItWasGiven() throws {
        for (number, name) in ["hero", "shared", "widgets"].enumerated() {
            try fixture.writeScreenshot(
                locale: "en-US", deviceClassID: DeviceClass.iPhone69.id,
                named: String(format: "%02d-\(name).png", number + 1), width: 1290, height: 2796
            )
        }

        try ContentWriter.reorderScreenshots(
            order: ["03-widgets.png", "01-hero.png", "02-shared.png"],
            locale: "en-US",
            deviceClass: .iPhone69,
            at: .version("1.0"),
            in: fixture.load()
        )

        #expect(try slot() == [
            "01-widgets-iPhone-6.9-en_US.png",
            "02-hero-iPhone-6.9-en_US.png",
            "03-shared-iPhone-6.9-en_US.png"
        ])
    }

    @Test func takesAFullFileNameAsWellAsASlug() throws {
        try fixture.writeScreenshot(
            locale: "en-US", deviceClassID: DeviceClass.iPhone69.id,
            named: "01-hero.png", width: 1290, height: 2796
        )
        try fixture.writeScreenshot(
            locale: "en-US", deviceClassID: DeviceClass.iPhone69.id,
            named: "02-shared.png", width: 1290, height: 2796
        )

        try ContentWriter.reorderScreenshots(
            order: ["02-shared.png", "01-hero.png"],
            locale: "en-US",
            deviceClass: .iPhone69,
            at: .version("1.0"),
            in: fixture.load()
        )

        #expect(try slot() == ["01-shared-iPhone-6.9-en_US.png", "02-hero-iPhone-6.9-en_US.png"])
    }

    /// An order that names only some of the set would quietly drop the rest to
    /// the end, which is not what anybody meant by that list.
    @Test func refusesAnOrderThatLeavesAScreenshotOut() throws {
        try fixture.writeScreenshot(
            locale: "en-US", deviceClassID: DeviceClass.iPhone69.id,
            named: "01-hero.png", width: 1290, height: 2796
        )
        try fixture.writeScreenshot(
            locale: "en-US", deviceClassID: DeviceClass.iPhone69.id,
            named: "02-shared.png", width: 1290, height: 2796
        )

        let error = #expect(throws: ContentWriteError.self) {
            try ContentWriter.reorderScreenshots(
                order: ["01-hero.png"],
                locale: "en-US",
                deviceClass: .iPhone69,
                at: .version("1.0"),
                in: self.fixture.load()
            )
        }
        #expect("\(error!)".contains("02-shared.png"))
    }

    @Test func refusesAnOrderNamingSomethingThatIsNotThere() throws {
        try fixture.writeScreenshot(
            locale: "en-US", deviceClassID: DeviceClass.iPhone69.id,
            named: "01-hero.png", width: 1290, height: 2796
        )

        #expect(throws: ContentWriteError.self) {
            try ContentWriter.reorderScreenshots(
                order: ["01-nothing.png"],
                locale: "en-US",
                deviceClass: .iPhone69,
                at: .version("1.0"),
                in: self.fixture.load()
            )
        }
    }

    // MARK: - Removing

    @Test func closesTheGapAfterARemoval() throws {
        for (number, name) in ["hero", "shared", "widgets"].enumerated() {
            try fixture.writeScreenshot(
                locale: "en-US", deviceClassID: DeviceClass.iPhone69.id,
                named: String(format: "%02d-\(name).png", number + 1), width: 1290, height: 2796
            )
        }

        try ContentWriter.removeScreenshots(
            named: ["02-shared.png"],
            locale: "en-US",
            deviceClass: .iPhone69,
            at: .version("1.0"),
            in: fixture.load()
        )

        #expect(try slot() == ["01-hero-iPhone-6.9-en_US.png", "02-widgets-iPhone-6.9-en_US.png"])
    }

    @Test func refusesToRemoveSomethingThatIsNotThere() throws {
        try fixture.writeScreenshot(
            locale: "en-US", deviceClassID: DeviceClass.iPhone69.id,
            named: "01-hero.png", width: 1290, height: 2796
        )

        #expect(throws: ContentWriteError.self) {
            try ContentWriter.removeScreenshots(
                named: ["shared"],
                locale: "en-US",
                deviceClass: .iPhone69,
                at: .version("1.0"),
                in: self.fixture.load()
            )
        }
        #expect(try slot() == ["01-hero.png"])
    }

    // MARK: - Explaining a refusal

    @Test func saysNothingAboutAnImageThatFits() throws {
        let incoming = try makeIncoming()
        let url = try makeImage(in: incoming, named: "hero.png")

        #expect(ContentWriter.reasonToRefuse(ImageInspector.inspect(url: url), for: .iPhone69) == nil)
    }

    @Test func saysAFileThatIsNotAnImageCouldNotBeRead() throws {
        let incoming = try makeIncoming()
        let url = incoming.appending(path: "notes.txt")
        try Data("not an image".utf8).write(to: url)

        let reason = try #require(ContentWriter.reasonToRefuse(
            ImageInspector.inspect(url: url),
            for: .iPhone69
        ))
        #expect(reason.contains("could not be read"))
    }
}
