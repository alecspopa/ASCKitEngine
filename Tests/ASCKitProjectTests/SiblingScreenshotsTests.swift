import Foundation
import Testing
@testable import ASCKitProject

/// A class rather than a struct, so `deinit` can remove the temporary folder
/// each test builds.
final class SiblingScreenshotsTests {
    let fixture: FixtureProject

    init() throws {
        fixture = try FixtureProject()
    }

    deinit {
        fixture.remove()
    }

    // MARK: - Helpers

    let deviceClass = DeviceClass.iPhone69

    /// Two Spanishes and one English, which is the shape the rule is about.
    func makeProject(
        locales: [String] = ["en-US", "es-ES", "es-MX"],
        usesSourceScreenshots: [String: [String]] = [:],
        copiesScreenshotsFrom: [String: [String: String]] = [:]
    ) throws {
        try fixture.writeConfig(ProjectConfig(
            bundleID: "com.example.MyApp",
            keyID: "ABC123",
            issuerID: "issuer",
            locales: locales,
            deviceClasses: [deviceClass.id],
            usesSourceScreenshots: usesSourceScreenshots,
            copiesScreenshotsFrom: copiesScreenshotsFrom
        ))
    }

    /// Writes one set, with the date said out loud so the test is about the
    /// rule rather than about how fast the machine wrote two folders.
    func writeSet(
        _ locale: String,
        slugs: [String],
        modified: Date,
        seedPrefix: String? = nil
    ) throws {
        let size = deviceClass.acceptedSizes[0]
        for (index, slug) in slugs.enumerated() {
            try fixture.writeScreenshot(
                locale: locale,
                deviceClassID: deviceClass.id,
                named: String(format: "%02d-\(slug).png", index + 1),
                width: size.width,
                height: size.height,
                seed: seedPrefix.map { "\($0)/\(slug)" }
            )
        }
        try fixture.setModified(locale: locale, deviceClassID: deviceClass.id, to: modified)
    }

    func offers() throws -> [SiblingScreenshots.Offer] {
        let project = try fixture.load()
        return try SiblingScreenshots.offers(in: fixture.content(), config: project.config)
    }

    let older = Date(timeIntervalSince1970: 1_700_000_000)
    let newer = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: - Finding the newer set

    @Test("The language with the older screenshots is offered the newer ones")
    func offersFromTheNewerSibling() throws {
        try makeProject()
        try writeSet("en-US", slugs: ["running-low", "shared"], modified: newer)
        try writeSet("es-ES", slugs: ["running-low", "shared"], modified: older)
        try writeSet("es-MX", slugs: ["running-low", "shared"], modified: newer)

        let found = try offers()
        #expect(found.count == 1)
        #expect(found.first?.locale == "es-ES")
        #expect(found.first?.from == "es-MX")
        #expect(found.first?.fileCount == 2)
        #expect(found.first?.current == older)
    }

    @Test("The English screenshots are never offered to a Spanish language")
    func neverOffersAcrossBaseLanguages() throws {
        try makeProject(locales: ["en-US", "es-ES"])
        try writeSet("en-US", slugs: ["running-low", "shared"], modified: newer)
        try writeSet("es-ES", slugs: ["running-low"], modified: older)

        #expect(try offers().isEmpty)
    }

    @Test("A language with no screenshots is offered its sibling's")
    func offersToAnEmptyLanguage() throws {
        try makeProject()
        try writeSet("en-US", slugs: ["running-low"], modified: newer)
        try writeSet("es-MX", slugs: ["running-low", "shared"], modified: newer)

        let found = try offers()
        #expect(found.count == 1)
        #expect(found.first?.locale == "es-ES")
        #expect(found.first?.from == "es-MX")
        #expect(found.first?.current == nil)
    }

    @Test("Two languages holding the same pictures are offered nothing")
    func offersNothingWhenThePicturesMatch() throws {
        try makeProject()
        try writeSet("en-US", slugs: ["running-low"], modified: older)
        try writeSet("es-ES", slugs: ["running-low"], modified: older, seedPrefix: "spanish")
        try writeSet("es-MX", slugs: ["running-low"], modified: newer, seedPrefix: "spanish")

        #expect(try offers().isEmpty)
    }

    @Test("The older language is offered nothing")
    func offersOnlyToTheOlderSide() throws {
        try makeProject()
        try writeSet("en-US", slugs: ["running-low"], modified: newer)
        try writeSet("es-ES", slugs: ["running-low"], modified: older)
        try writeSet("es-MX", slugs: ["running-low"], modified: newer)

        #expect(try offers().map(\.locale) == ["es-ES"])
    }

    @Test("The newest of three siblings is the one offered")
    func picksTheNewestOfSeveral() throws {
        try makeProject(locales: ["en-US", "en-GB", "en-AU"])
        try writeSet("en-US", slugs: ["running-low"], modified: older)
        try writeSet("en-GB", slugs: ["running-low"], modified: Date(timeIntervalSince1970: 1_750_000_000))
        try writeSet("en-AU", slugs: ["running-low"], modified: newer)

        let found = try offers()
        #expect(found.first { $0.locale == "en-US" }?.from == "en-AU")
        #expect(found.first { $0.locale == "en-GB" }?.from == "en-AU")
    }

    @Test("A language set to show the source language's screenshots is offered nothing")
    func saysNothingAboutADecision() throws {
        try makeProject(
            locales: ["en-US", "en-GB"],
            usesSourceScreenshots: ["en-GB": [DeviceClass.iPhone69.id]]
        )
        try writeSet("en-US", slugs: ["running-low"], modified: newer)

        #expect(try offers().isEmpty)
    }

    @Test("Simplified and traditional Chinese are different languages here")
    func keepsTheScriptsApart() throws {
        try makeProject(locales: ["zh-Hans", "zh-Hant"])
        try writeSet("zh-Hans", slugs: ["running-low"], modified: newer)
        try writeSet("zh-Hant", slugs: ["running-low"], modified: older)

        #expect(try offers().isEmpty)
    }

    // MARK: - Doing the copy

    @Test("The copy leaves the two languages holding the same pictures")
    func copyMakesTheSetsMatch() throws {
        try makeProject()
        try writeSet("en-US", slugs: ["running-low"], modified: newer)
        try writeSet("es-ES", slugs: ["running-low"], modified: older)
        try writeSet("es-MX", slugs: ["running-low", "shared", "cupboard"], modified: newer)

        let offer = try #require(try offers().first)
        let landed = try SiblingScreenshots.accept(offer, version: fixture.version, in: fixture.load())

        // The names say es-ES, not the es-MX they were copied from. The folder
        // decides the language a name says.
        #expect(landed.map(\.fileName) == [
            "01-running-low-iPhone-6.9-es_ES.png",
            "02-shared-iPhone-6.9-es_ES.png",
            "03-cupboard-iPhone-6.9-es_ES.png"
        ])
        let donor = try fixture.content().screenshots(
            locale: "es-MX", deviceClassID: deviceClass.id
        )
        #expect(landed.map(\.byteCount) == donor.map(\.byteCount))
    }

    @Test("A file the newer set has no name for goes to the Trash")
    func copyTakesTheLeftoversAway() throws {
        try makeProject()
        try writeSet("en-US", slugs: ["running-low"], modified: newer)
        try writeSet("es-ES", slugs: ["running-low", "gone"], modified: older)
        try writeSet("es-MX", slugs: ["running-low"], modified: newer)

        let offer = try #require(try offers().first)
        let landed = try SiblingScreenshots.accept(offer, version: fixture.version, in: fixture.load())
        #expect(landed.map(\.fileName) == ["01-running-low-iPhone-6.9-es_ES.png"])
    }

    @Test("A copy from a different language is refused")
    func refusesADifferentLanguage() throws {
        try makeProject()
        try writeSet("en-US", slugs: ["running-low"], modified: newer)
        try writeSet("es-ES", slugs: ["running-low"], modified: older)

        #expect(throws: SiblingScreenshotError.self) {
            try SiblingScreenshots.copy(
                from: "en-US",
                to: "es-ES",
                deviceClassID: self.deviceClass.id,
                version: self.fixture.version,
                in: self.fixture.load()
            )
        }
    }

    @Test("A copy from a language this project does not ship is refused")
    func refusesALanguageNotShipped() throws {
        try makeProject(locales: ["es-ES"])
        try writeSet("es-ES", slugs: ["running-low"], modified: older)

        #expect(throws: SiblingScreenshotError.self) {
            try SiblingScreenshots.copy(
                from: "es-MX",
                to: "es-ES",
                deviceClassID: self.deviceClass.id,
                version: self.fixture.version,
                in: self.fixture.load()
            )
        }
    }

    @Test("A copy from an empty set is refused")
    func refusesAnEmptyDonor() throws {
        try makeProject()
        try writeSet("es-ES", slugs: ["running-low"], modified: older)

        #expect(throws: SiblingScreenshotError.self) {
            try SiblingScreenshots.copy(
                from: "es-MX",
                to: "es-ES",
                deviceClassID: self.deviceClass.id,
                version: self.fixture.version,
                in: self.fixture.load()
            )
        }
    }

    @Test("The copy answers the check, so the offer is gone afterwards")
    func copyAnswersTheOffer() throws {
        try makeProject()
        try writeSet("en-US", slugs: ["running-low"], modified: newer)
        try writeSet("es-ES", slugs: ["running-low"], modified: older)
        try writeSet("es-MX", slugs: ["running-low", "shared"], modified: newer)

        let offer = try #require(try offers().first)
        try SiblingScreenshots.accept(offer, version: fixture.version, in: fixture.load())

        #expect(try offers().isEmpty)
    }

    // MARK: - Remembering the copy

    func copy(from donor: String, to locale: String, in project: Project? = nil) throws {
        try SiblingScreenshots.copy(
            from: donor,
            to: locale,
            deviceClassID: deviceClass.id,
            version: fixture.version,
            in: project ?? fixture.load()
        )
    }

    func rememberedCopies() throws -> [String: [String: String]] {
        try fixture.load().config.copiesScreenshotsFrom
    }

    @Test("A copy is written into the configuration file")
    func copyIsRemembered() throws {
        try makeProject()
        try writeSet("es-MX", slugs: ["running-low"], modified: newer)

        try copy(from: "es-MX", to: "es-ES")

        #expect(try rememberedCopies() == ["es-ES": [deviceClass.id: "es-MX"]])
    }

    @Test("A copy the other way takes the older direction out")
    func copyTheOtherWayReplacesTheOlderDirection() throws {
        try makeProject()
        try writeSet("es-MX", slugs: ["running-low"], modified: newer)

        try copy(from: "es-MX", to: "es-ES")
        try copy(from: "es-ES", to: "es-MX")

        #expect(try rememberedCopies() == ["es-MX": [deviceClass.id: "es-ES"]])
    }

    /// `asckit copy-screenshots --all` reads the folder once and makes every
    /// copy from that read.
    @Test("Two copies made from one read of the folder are both remembered")
    func everyCopyFromOneReadIsRemembered() throws {
        try makeProject(locales: ["en-US", "en-GB", "es-ES", "es-MX"])
        try writeSet("en-US", slugs: ["running-low"], modified: newer)
        try writeSet("es-MX", slugs: ["running-low"], modified: newer)

        let project = try fixture.load()
        try copy(from: "en-US", to: "en-GB", in: project)
        try copy(from: "es-MX", to: "es-ES", in: project)

        #expect(try rememberedCopies() == [
            "en-GB": [deviceClass.id: "en-US"],
            "es-ES": [deviceClass.id: "es-MX"]
        ])
    }

    @Test("A refused copy is not remembered")
    func refusedCopyIsNotRemembered() throws {
        try makeProject()
        try writeSet("es-ES", slugs: ["running-low"], modified: older)

        #expect(throws: SiblingScreenshotError.self) {
            try self.copy(from: "es-MX", to: "es-ES")
        }
        #expect(try rememberedCopies().isEmpty)
    }

    @Test("Forgetting the last copy of a language takes the language out")
    func forgetTakesTheLanguageOut() throws {
        try makeProject(copiesScreenshotsFrom: ["es-ES": [deviceClass.id: "es-MX"]])

        let config = try SiblingScreenshots.forget(
            locale: "es-ES", deviceClassID: deviceClass.id, in: fixture.load()
        )

        #expect(config.copiesScreenshotsFrom.isEmpty)
        #expect(try rememberedCopies().isEmpty)
    }

    // MARK: - Making the remembered copies

    func copyRemembered(after changed: Set<ScreenshotSlot>? = nil) throws -> [SiblingScreenshots.Remembered] {
        try SiblingScreenshots.copyRemembered(version: fixture.version, in: fixture.load(), after: changed)
    }

    func fileNames(_ locale: String) throws -> [String] {
        try fixture.content().screenshots(locale: locale, deviceClassID: deviceClass.id).map(\.fileName)
    }

    @Test("A remembered copy is made in a version that does not hold it")
    func makesARememberedCopy() throws {
        try makeProject(copiesScreenshotsFrom: ["es-ES": [deviceClass.id: "es-MX"]])
        try writeSet("es-MX", slugs: ["running-low", "shared"], modified: newer)

        let made = try copyRemembered()

        #expect(made == [SiblingScreenshots.Remembered(
            locale: "es-ES", from: "es-MX", deviceClass: deviceClass, count: 2, trashed: 0
        )])
        #expect(try fileNames("es-ES") == [
            "01-running-low-iPhone-6.9-es_ES.png",
            "02-shared-iPhone-6.9-es_ES.png"
        ])
    }

    @Test("A newer set takes the place of the older one, which goes to the Trash")
    func replacesTheOlderSet() throws {
        try makeProject(copiesScreenshotsFrom: ["es-ES": [deviceClass.id: "es-MX"]])
        try writeSet("es-ES", slugs: ["running-low", "gone"], modified: older)
        try writeSet("es-MX", slugs: ["running-low"], modified: newer)

        let made = try copyRemembered()

        #expect(made.map(\.trashed) == [2])
        #expect(try fileNames("es-ES") == ["01-running-low-iPhone-6.9-es_ES.png"])
    }

    /// The export landed in `es-ES` this time. The setting names the other
    /// direction, and following it would put the new pictures in the Trash.
    @Test("A language that holds the newer set keeps it")
    func keepsTheNewerSet() throws {
        try makeProject(copiesScreenshotsFrom: ["es-ES": [deviceClass.id: "es-MX"]])
        try writeSet("es-ES", slugs: ["running-low", "shared"], modified: newer)
        try writeSet("es-MX", slugs: ["running-low"], modified: older)

        #expect(try copyRemembered().isEmpty)
        #expect(try fileNames("es-ES").count == 2)
    }

    /// Filing German pictures never moves a Spanish file, even with a Spanish
    /// copy waiting to be made.
    @Test("Only a language that copies a set that changed takes a copy")
    func looksOnlyAtTheSetsThatChanged() throws {
        try makeProject(
            locales: ["en-US", "de-DE", "es-ES", "es-MX"],
            copiesScreenshotsFrom: ["es-ES": [deviceClass.id: "es-MX"]]
        )
        try writeSet("es-MX", slugs: ["running-low"], modified: newer)

        let german = ScreenshotSlot(locale: "de-DE", deviceClassID: deviceClass.id)
        let mexican = ScreenshotSlot(locale: "es-MX", deviceClassID: deviceClass.id)

        #expect(try copyRemembered(after: [german]).isEmpty)
        #expect(try copyRemembered(after: [mexican]).map(\.locale) == ["es-ES"])
    }

    @Test("Two languages that hold the same pictures are left alone")
    func leavesTheSamePicturesAlone() throws {
        try makeProject(copiesScreenshotsFrom: ["es-ES": [deviceClass.id: "es-MX"]])
        try writeSet("es-ES", slugs: ["running-low"], modified: older, seedPrefix: "spanish")
        try writeSet("es-MX", slugs: ["running-low"], modified: newer, seedPrefix: "spanish")

        #expect(try copyRemembered().isEmpty)
    }

    @Test("A language with nothing to give leaves the other set as it is")
    func leavesTheSetWhenTheDonorIsEmpty() throws {
        try makeProject(copiesScreenshotsFrom: ["es-ES": [deviceClass.id: "es-MX"]])
        try writeSet("es-ES", slugs: ["running-low"], modified: older)

        #expect(try copyRemembered().isEmpty)
        #expect(try fixture.content().screenshots(locale: "es-ES", deviceClassID: deviceClass.id).count == 1)
    }

    /// `en-AU` copies `en-GB`, which copies `en-US`. The alphabet puts `en-AU`
    /// first, and the pictures have to get to `en-GB` before it can give them.
    @Test("A chain of copies is made in the order the pictures travel")
    func makesAChainInOrder() throws {
        try makeProject(
            locales: ["en-US", "en-AU", "en-GB"],
            copiesScreenshotsFrom: [
                "en-AU": [deviceClass.id: "en-GB"],
                "en-GB": [deviceClass.id: "en-US"]
            ]
        )
        try writeSet("en-US", slugs: ["running-low", "shared"], modified: newer)

        let made = try copyRemembered()

        #expect(made.map(\.locale) == ["en-GB", "en-AU"])
        #expect(made.map(\.from) == ["en-US", "en-GB"])
        #expect(try fileNames("en-AU").count == 2)
    }

    @Test("Pictures that arrive in the middle of a chain go on from there")
    func followsAChangeInTheMiddleOfAChain() throws {
        try makeProject(
            locales: ["en-US", "en-AU", "en-GB"],
            copiesScreenshotsFrom: [
                "en-AU": [deviceClass.id: "en-GB"],
                "en-GB": [deviceClass.id: "en-US"]
            ]
        )
        try writeSet("en-US", slugs: ["running-low"], modified: older)
        try writeSet("en-GB", slugs: ["running-low", "shared"], modified: newer)

        let british = ScreenshotSlot(locale: "en-GB", deviceClassID: deviceClass.id)
        let made = try copyRemembered(after: [british])

        #expect(made.map(\.locale) == ["en-AU"])
        #expect(try fileNames("en-GB").count == 2)
    }

    @Test("A language set to show the source language's screenshots takes no copy")
    func leavesADecisionAlone() throws {
        try makeProject(
            locales: ["en-US", "en-AU", "en-GB"],
            usesSourceScreenshots: ["en-GB": [DeviceClass.iPhone69.id]],
            copiesScreenshotsFrom: ["en-GB": [DeviceClass.iPhone69.id: "en-AU"]]
        )
        try writeSet("en-AU", slugs: ["running-low"], modified: newer)

        #expect(try copyRemembered().isEmpty)
    }

    @Test("A copy that cannot be made is left out", arguments: [
        ["es-ES": [DeviceClass.iPhone69.id: "en-US"]],
        ["es-ES": [DeviceClass.iPhone69.id: "es-419"]],
        ["es-ES": [DeviceClass.iPad13.id: "es-MX"]],
        ["es-ES": [DeviceClass.iPhone69.id: "es-MX"], "es-MX": [DeviceClass.iPhone69.id: "es-ES"]]
    ])
    func leavesOutACopyThatCannotBeMade(copies: [String: [String: String]]) throws {
        try makeProject(copiesScreenshotsFrom: copies)
        try writeSet("en-US", slugs: ["running-low"], modified: newer)
        try writeSet("es-MX", slugs: ["running-low"], modified: newer)

        #expect(try copyRemembered().isEmpty)
    }
}
