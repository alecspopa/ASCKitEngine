import Foundation
import Testing
@testable import ASCKitProject

/// A class rather than a struct, so `deinit` can remove the temporary folder
/// each test builds.
final class ValidatorTests {
    let fixture: FixtureProject

    init() throws {
        fixture = try FixtureProject()
    }

    deinit {
        fixture.remove()
    }

    // MARK: - Helpers

    /// Everything App Store Connect needs, so that a test breaking one thing
    /// sees only that one thing.
    func goodFields(name: String = "Stocked") -> AppInformation.Fields {
        AppInformation.Fields(
            name: name,
            subtitle: "Shared grocery and pantry list",
            keywords: "household,inventory,restock",
            description: "Know what you have and what you need.",
            whatsNew: "First release.",
            supportUrl: "https://example.com/support",
            privacyPolicyUrl: "https://example.com/privacy"
        )
    }

    /// The smallest project that has nothing wrong with it. Every test below
    /// breaks exactly one thing about it.
    func makeCleanProject(
        locales: [String] = ["en-US"],
        deviceClasses: [String] = [DeviceClass.iPhone69.id]
    ) throws {
        try fixture.writeConfig(ProjectConfig(
            bundleID: "com.example.MyApp",
            keyID: "ABC123",
            issuerID: "issuer",
            locales: locales,
            deviceClasses: deviceClasses
        ))
        let source = goodFields()
        for locale in locales {
            var fields = source
            if locale != "en-US" {
                fields.name = "Translated name"
                fields.subtitle = "Translated subtitle"
                fields.keywords = "translated,keywords"
                fields.description = "Translated description."
                fields.whatsNew = "Translated release."
            }
            try fixture.writeCopy(AppInformation(
                locale: locale,
                status: .approved,
                fields: fields
            ))
            for deviceClass in deviceClasses.compactMap(DeviceClass.named) {
                // Each device class takes its own sizes, so the picture has to
                // be the size the one it is written for accepts.
                let size = deviceClass.acceptedSizes[0]
                try fixture.writeScreenshot(
                    locale: locale,
                    deviceClassID: deviceClass.id,
                    named: screenshotName("running-low", locale: locale, deviceClass: deviceClass),
                    width: size.width,
                    height: size.height
                )
            }
        }
    }

    /// Says that these languages show the source language's screenshots, in the
    /// configuration the project has now.
    func useSourceScreenshots(_ map: [String: [String]]) throws {
        var config = try fixture.load().config
        config.usesSourceScreenshots = map
        try fixture.writeConfig(config)
    }

    // MARK: - The baseline

    /// An iPhone app with no iPhone Duo screenshots gets a warning, so the
    /// clean project lists them.
    @Test func findsNothingWrongWithACleanProject() throws {
        try makeCleanProject(deviceClasses: [DeviceClass.iPhone69.id, DeviceClass.iPhoneDuo.id])
        let problems = try fixture.problems()
        #expect(problems.isEmpty, "unexpected: \(problems.map(\.message.english))")
    }

    /// The fixture writer has to actually produce what it claims, or every
    /// screenshot test below is meaningless.
    @Test func writesScreenshotsWithTheSizeAndAlphaItClaims() throws {
        try fixture.writeScreenshot(
            locale: "en-US", deviceClassID: "iphone-6.9",
            named: "opaque.png", width: 1320, height: 2868, hasAlpha: false
        )
        try fixture.writeScreenshot(
            locale: "en-US", deviceClassID: "iphone-6.9",
            named: "transparent.png", width: 1320, height: 2868, hasAlpha: true
        )
        let directory = fixture.screenshotsDirectory(locale: "en-US", deviceClassID: "iphone-6.9")

        let opaque = ImageInspector.inspect(url: directory.appending(path: "opaque.png"))
        #expect(opaque.pixelWidth == 1320)
        #expect(opaque.pixelHeight == 2868)
        #expect(opaque.hasAlpha == false)

        let transparent = ImageInspector.inspect(url: directory.appending(path: "transparent.png"))
        #expect(transparent.hasAlpha == true)
    }

    // MARK: - Configuration

    @Test func refusesALocaleAppStoreConnectDoesNotAcceptAndSaysWhichToUse() throws {
        try makeCleanProject(locales: ["en-US", "ja-JP"])
        let problem = try #require(try fixture.problems().first { $0.locale == "ja-JP" && $0.area == .configuration })
        #expect(problem.severity == .error)
        #expect(problem.fix?.english == "Use ja instead.")
    }

    @Test func refusesADeviceClassItDoesNotKnow() throws {
        try fixture.writeConfig(ProjectConfig(
            bundleID: "com.example.MyApp", keyID: "ABC123",
            locales: ["en-US"], deviceClasses: ["iphone-7.2"]
        ))
        try fixture.writeCopy(AppInformation(locale: "en-US", status: .approved, fields: goodFields()))

        let problems = try fixture.problems()
        #expect(problems.contains { $0.area == .configuration && $0.deviceClassID == "iphone-7.2" })
    }

    @Test func refusesASourceLanguageThatIsNotInTheList() throws {
        try fixture.writeConfig(ProjectConfig(
            bundleID: "com.example.MyApp", keyID: "ABC123",
            sourceLocale: "en-GB", locales: ["en-US"]
        ))
        let problems = try fixture.problems()
        #expect(problems.contains { $0.kind == .sourceLocaleNotListed })
    }

    // MARK: - Layout

    @Test func warnsAboutALanguageWithNoCopyFile() throws {
        try makeCleanProject()
        try fixture.writeConfig(ProjectConfig(
            bundleID: "com.example.MyApp", keyID: "ABC123",
            locales: ["en-US", "de-DE"], deviceClasses: [DeviceClass.iPhone69.id]
        ))
        let problem = try #require(try fixture.problems().first { $0.locale == "de-DE" && $0.area == .layout })
        #expect(problem.severity == .warning)
        #expect(problem.kind == .appInformationFileMissing)
    }

    @Test func reportsACopyFileForALanguageThatIsNotListed() throws {
        try makeCleanProject()
        try fixture.writeCopy(AppInformation(locale: "fr-FR", status: .approved, fields: goodFields()))

        let problem = try #require(try fixture.problems().first { $0.locale == "fr-FR" })
        #expect(problem.severity == .warning)
        #expect(problem.kind == .appInformationFileNotListed)
    }

    @Test func reportsACopyFileItCannotRead() throws {
        try makeCleanProject()
        try fixture.writeRawCopy("{ this is not json", locale: "en-US")

        let problem = try #require(try fixture.problems().first { $0.area == .layout })
        #expect(problem.severity == .error)
        #expect(problem.kind == .appInformationUnreadable)
    }

    /// The file name decides which language a file is for, so a locale field
    /// that disagrees is a trap rather than a preference.
    @Test func reportsALocaleFieldThatDisagreesWithTheFileName() throws {
        try makeCleanProject()
        try fixture.writeCopy(
            AppInformation(locale: "de-DE", status: .approved, fields: goodFields()),
            named: "en-US.json"
        )
        let problem = try #require(try fixture.problems().first { $0.area == .layout })
        #expect(problem.severity == .error)
        #expect(problem.kind == .appInformationLocaleMismatch)
        #expect(problem.message.english.contains("de-DE"))
    }

    // MARK: - Copy

    @Test func reportsAFieldOverItsLimitWithTheRealCount() throws {
        try makeCleanProject()
        var fields = goodFields()
        fields.subtitle = String(repeating: "a", count: 31)
        try fixture.writeCopy(AppInformation(locale: "en-US", status: .approved, fields: fields))

        let problem = try #require(try fixture.problems().first { $0.field == .subtitle })
        #expect(problem.severity == .error)
        #expect(problem.message.english == "subtitle is 31 characters, and the limit is 30.")
        // The noun ends where the string catalog's plural rule says.
        #expect(problem.fix?.english == "Cut 1 character.")
    }

    /// The keyword case is the one worth getting right. These 86 characters are
    /// 258 UTF-8 bytes, and App Store Connect takes them.
    @Test func acceptsJapaneseKeywordsThatAreOverAHundredBytes() throws {
        try makeCleanProject()
        var fields = goodFields()
        fields.keywords = String(repeating: "家", count: 86)
        try fixture.writeCopy(AppInformation(locale: "en-US", status: .approved, fields: fields))

        #expect(try fixture.problems().contains { $0.field == .keywords } == false)
    }

    @Test func reportsKeywordsThatAreOverTheCharacterLimit() throws {
        try makeCleanProject()
        var fields = goodFields()
        fields.keywords = String(repeating: "家", count: 120)
        try fixture.writeCopy(AppInformation(locale: "en-US", status: .approved, fields: fields))

        let problem = try #require(try fixture.problems().first { $0.field == .keywords })
        #expect(problem.message.english == "keywords is 120 characters, and the limit is 100.")
        #expect(problem.fix?.english == "Cut 20 characters.")
    }

    @Test func reportsANameShorterThanApplesMinimum() throws {
        try makeCleanProject()
        try fixture.writeCopy(AppInformation(locale: "en-US", status: .approved, fields: goodFields(name: "S")))

        let problem = try #require(try fixture.problems().first { $0.field == .name })
        #expect(problem.message.english.contains("minimum is 2"))
    }

    /// An empty value is published, and it blanks the field on the store. A
    /// missing field leaves it alone, which is almost always what was meant.
    @Test func reportsAnEmptyFieldRatherThanBlankingTheStore() throws {
        try makeCleanProject()
        var fields = goodFields()
        fields.promotionalText = "   "
        try fixture.writeCopy(AppInformation(locale: "en-US", status: .approved, fields: fields))

        let problem = try #require(try fixture.problems().first { $0.field == .promotionalText })
        #expect(problem.severity == .error)
        #expect(problem.fix?.english.contains("Remove the field") == true)
    }

    @Test func reportsASupportAddressThatIsNotHTTPS() throws {
        try makeCleanProject()
        var fields = goodFields()
        fields.supportUrl = "http://example.com/support"
        try fixture.writeCopy(AppInformation(locale: "en-US", status: .approved, fields: fields))

        #expect(try fixture.problems().contains { $0.field == .supportUrl && $0.severity == .error })
    }

    @Test func warnsAboutSpacesAfterCommasInKeywords() throws {
        try makeCleanProject()
        var fields = goodFields()
        fields.keywords = "household, inventory, restock"
        try fixture.writeCopy(AppInformation(locale: "en-US", status: .approved, fields: fields))

        let problem = try #require(try fixture.problems().first { $0.field == .keywords })
        #expect(problem.severity == .warning)
        #expect(problem.fix?.english.contains("costs a character") == true)
    }

    @Test func warnsWhenALanguageIsNotApprovedYet() throws {
        try makeCleanProject()
        try fixture.writeCopy(AppInformation(locale: "en-US", status: .needsHuman, fields: goodFields()))

        let problem = try #require(try fixture.problems().first { $0.kind == .statusNotPublishable })
        #expect(problem.severity == .warning)
        #expect(problem.message.english.contains("needs_human"))
        #expect(problem.fix?.english.contains("set status to approved") == true)
    }

    @Test func leavesALanguageAMachineApprovedAlone() throws {
        try makeCleanProject()
        try fixture.writeCopy(AppInformation(locale: "en-US", status: .aiApproved, fields: goodFields()))

        #expect(try fixture.problems().contains { $0.kind == .statusNotPublishable } == false)
    }

    // MARK: - Words of its own

    /// Every language holds its own words. Rewriting the source language says
    /// nothing about any other language, so nothing is reported.
    @Test func saysNothingAboutOtherLanguagesWhenTheSourceIsRewritten() throws {
        try makeCleanProject(locales: ["en-US", "de-DE"])
        var changed = goodFields()
        changed.subtitle = "A different subtitle entirely"
        changed.description = "Different words entirely."
        try fixture.writeCopy(AppInformation(locale: "en-US", status: .approved, fields: changed))

        #expect(try fixture.problems().contains { $0.locale == "de-DE" } == false)
    }

    /// A field the source language fills and this one leaves empty is worth
    /// saying, even where App Store Connect would accept the submission.
    @Test func warnsWhenALanguageHasNoWordsOfItsOwnForAField() throws {
        try makeCleanProject(locales: ["en-US", "de-DE"])
        var german = goodFields()
        german.name = "Translated name"
        german.subtitle = nil
        try fixture.writeCopy(AppInformation(locale: "de-DE", status: .approved, fields: german))

        let problem = try #require(try fixture.problems().first { $0.locale == "de-DE" && $0.field == .subtitle })
        #expect(problem.severity == .warning)
        #expect(problem.kind == .textNotTranslated)
        #expect(problem.message.english == "de-DE has no subtitle.")
    }

    /// The source language has nothing to be missing against.
    @Test func saysNothingAboutTheSourceLanguageLeavingAFieldOut() throws {
        try makeCleanProject()

        #expect(try fixture.problems().contains { $0.kind == .textNotTranslated } == false)
    }

    /// A web address is the same in every language on purpose, so an empty one
    /// is not words nobody wrote.
    @Test func saysNothingAboutAWebAddressALanguageLeavesOut() throws {
        try makeCleanProject(locales: ["en-US", "de-DE"])
        var german = goodFields()
        german.name = "Translated name"
        german.marketingUrl = nil
        try fixture.writeCopy(AppInformation(locale: "de-DE", status: .approved, fields: german))

        #expect(try fixture.problems().contains {
            $0.locale == "de-DE" && $0.field == .marketingUrl
        } == false)
    }

    // MARK: - Screenshots

    @Test func reportsAScreenshotOfTheWrongSize() throws {
        try makeCleanProject()
        try fixture.writeScreenshot(
            locale: "en-US", deviceClassID: DeviceClass.iPhone69.id,
            named: "02-shared.png", width: 1206, height: 2622
        )
        let problem = try #require(try fixture.problems().first { $0.path?.contains("02-shared") == true })
        #expect(problem.severity == .error)
        #expect(problem.message.english.contains("1206x2622"))
        #expect(problem.fix?.english.contains("1320x2868") == true)
    }

    @Test func reportsAScreenshotWithAnAlphaChannel() throws {
        try makeCleanProject()
        try fixture.writeScreenshot(
            locale: "en-US", deviceClassID: DeviceClass.iPhone69.id,
            named: "02-shared.png", width: 1320, height: 2868, hasAlpha: true
        )
        let problem = try #require(try fixture.problems().first { $0.kind == .screenshotHasAlpha })
        #expect(problem.severity == .error)
    }

    /// A language that reads the same words has a checkbox for saying the
    /// empty folder is on purpose, so an empty folder without it blocks.
    @Test func reportsALanguageWithNoScreenshotsAtAll() throws {
        try makeCleanProject(locales: ["en-US", "en-GB"])
        try FileManager.default.removeItem(
            at: fixture.screenshotsDirectory(locale: "en-GB", deviceClassID: DeviceClass.iPhone69.id)
        )
        let problem = try #require(try fixture.problems().first { $0.locale == "en-GB" && $0.area == .screenshots })
        #expect(problem.severity == .error)
        #expect(problem.kind == .screenshotsMissing)
    }

    // MARK: - Languages that show the source language's screenshots

    /// App Store Connect shows the primary language's screenshots to anybody
    /// whose language has none, so an empty folder can be the decision rather
    /// than the gap. Saying so is what turns the error off.
    @Test func saysNothingAboutALanguageThatShowsTheSourceScreenshots() throws {
        try makeCleanProject(locales: ["en-US", "en-GB"])
        try FileManager.default.removeItem(
            at: fixture.screenshotsDirectory(locale: "en-GB", deviceClassID: DeviceClass.iPhone69.id)
        )
        try useSourceScreenshots(["en-GB": [DeviceClass.iPhone69.id]])

        #expect(try fixture.problems().contains { $0.area == .screenshots } == false)
    }

    /// One device class at a time, because App Store Connect falls back one
    /// display type at a time. The iPad shows English and the iPhone does not.
    @Test func stillReportsADeviceClassThatWasNotNamed() throws {
        try makeCleanProject(locales: ["en-US", "en-GB"], deviceClasses: [
            DeviceClass.iPhone69.id, DeviceClass.iPad13.id
        ])
        for deviceClass in [DeviceClass.iPhone69, DeviceClass.iPad13] {
            try FileManager.default.removeItem(
                at: fixture.screenshotsDirectory(locale: "en-GB", deviceClassID: deviceClass.id)
            )
        }
        try useSourceScreenshots(["en-GB": [DeviceClass.iPad13.id]])

        let problems = try fixture.problems().filter { $0.locale == "en-GB" && $0.area == .screenshots }
        #expect(problems.count == 1)
        #expect(problems[0].message.english.contains("iPhone 6.9 inch"))
    }

    /// The tick wins over files of its own, and it is a decision, so the
    /// check says nothing about either.
    @Test func saysNothingWhenALanguageShowsTheSourceScreenshotsAndHasItsOwn() throws {
        try makeCleanProject(locales: ["en-US", "en-GB"])
        try useSourceScreenshots(["en-GB": [DeviceClass.iPhone69.id]])

        let problems = try fixture.problems().filter { $0.locale == "en-GB" && $0.area == .screenshots }
        #expect(problems.isEmpty)
    }

    @Test func reportsTheSourceLanguageShowingItsOwnScreenshots() throws {
        try makeCleanProject(locales: ["en-US", "de-DE"])
        try useSourceScreenshots(["en-US": [DeviceClass.iPhone69.id]])

        let problem = try #require(try fixture.problems().first { $0.area == .configuration })
        #expect(problem.severity == .error)
        #expect(problem.kind == .sourceLocaleUsesOwnScreenshots)
    }

    /// A typo here reads as silence, and silence reads as a language that is
    /// fine, so a name nobody ships has to be reported.
    @Test func reportsALanguageItDoesNotShip() throws {
        try makeCleanProject(locales: ["en-US", "de-DE"])
        try useSourceScreenshots(["fr-FR": [DeviceClass.iPhone69.id]])

        let problem = try #require(try fixture.problems().first { $0.kind == .sourceScreenshotsLocaleNotShipped })
        #expect(problem.severity == .error)
        #expect(problem.message.english.contains("fr-FR"))
    }

    @Test func reportsADeviceClassItDoesNotList() throws {
        try makeCleanProject(locales: ["en-US", "de-DE"])
        try useSourceScreenshots(["de-DE": [DeviceClass.iPad13.id]])

        let problem = try #require(try fixture.problems().first { $0.kind == .sourceScreenshotsDeviceClassNotListed })
        #expect(problem.severity == .error)
        #expect(problem.message.english.contains(DeviceClass.iPad13.id))
    }

    @Test func reportsMoreThanTenScreenshotsInOneSet() throws {
        try makeCleanProject()
        for index in 2 ... 11 {
            try fixture.writeScreenshot(
                locale: "en-US", deviceClassID: DeviceClass.iPhone69.id,
                named: String(format: "%02d-slot.png", index), width: 1320, height: 2868
            )
        }
        let problem = try #require(try fixture.problems().first { $0.kind == .screenshotsOverLimit })
        #expect(problem.severity == .error)
        #expect(problem.message.english.contains("11"))
    }

    /// Everything in the folder is uploaded, so a stray file has to be
    /// reported rather than quietly skipped.
    @Test func reportsAFileThatIsNotAnImage() throws {
        try makeCleanProject()
        try fixture.writeNonImage(
            locale: "en-US", deviceClassID: DeviceClass.iPhone69.id, named: "notes.txt"
        )
        let problem = try #require(try fixture.problems().first { $0.kind == .screenshotUnreadable })
        #expect(problem.severity == .error)
        #expect(problem.message.english.contains("notes.txt"))
    }

    @Test func warnsAboutAFileNameThatWillNotSort() throws {
        try makeCleanProject()
        try fixture.writeScreenshot(
            locale: "en-US", deviceClassID: DeviceClass.iPhone69.id,
            named: "shared.png", width: 1320, height: 2868
        )
        let problem = try #require(try fixture.problems().first { $0.kind == .screenshotHasNoNumber })
        #expect(problem.severity == .warning)
    }

    @Test func warnsWhenALanguageIsMissingASlotTheSourceLanguageHas() throws {
        try makeCleanProject(locales: ["en-US", "de-DE"])
        try fixture.writeScreenshot(
            locale: "en-US", deviceClassID: DeviceClass.iPhone69.id,
            named: "02-shared.png", width: 1320, height: 2868
        )
        let problem = try #require(try fixture.problems().first { $0.locale == "de-DE" && $0.kind == .screenshotsMissingSiblings })
        #expect(problem.severity == .warning)
        #expect(problem.message.english.contains("shared"))
    }

    @Test func matchesInboxNamesAcrossLanguages() throws {
        try makeCleanProject(
            locales: ["en-US", "ro"],
            deviceClasses: [DeviceClass.iPad13.id]
        )
        let size = DeviceClass.iPad13.acceptedSizes[0]
        try fixture.writeScreenshot(
            locale: "en-US", deviceClassID: DeviceClass.iPad13.id,
            named: "02-inventory-iPad-13-en_US.png", width: size.width, height: size.height
        )
        try fixture.writeScreenshot(
            locale: "ro", deviceClassID: DeviceClass.iPad13.id,
            named: "02-inventory-iPad-13-ro.png", width: size.width, height: size.height
        )

        let missing = try fixture.problems().filter {
            $0.locale == "ro" && $0.kind == .screenshotsMissingSiblings
        }
        #expect(missing.isEmpty)
    }

    // MARK: - Publishing gate

    @Test func onlyErrorsBlockPublishing() throws {
        try makeCleanProject()
        try fixture.writeCopy(AppInformation(locale: "en-US", status: .needsHuman, fields: goodFields()))

        let problems = try fixture.problems()
        #expect(problems.warnings.isEmpty == false)
        #expect(problems.blocksPublishing == false)
    }
}

extension ValidatorTests {
    // MARK: - Languages that read different words

    /// A language that reads different words has no checkbox, so an error would
    /// block the push with no button to press. App Store Connect accepts the
    /// listing and shows the English pictures, so this warns instead.
    @Test func warnsWhenAnotherLanguageHasNoScreenshotsOfItsOwn() throws {
        try makeCleanProject(locales: ["en-US", "de-DE"])
        try FileManager.default.removeItem(
            at: fixture.screenshotsDirectory(locale: "de-DE", deviceClassID: DeviceClass.iPhone69.id)
        )
        let problem = try #require(try fixture.problems().first { $0.locale == "de-DE" && $0.area == .screenshots })
        #expect(problem.severity == .warning)
        #expect(problem.kind == .screenshotsNotTranslated)
        #expect(try fixture.problems().blocksPublishing == false)
    }

    /// The checkbox is for a language that reads the same words. Naming one
    /// that reads different words is a decision nobody can defend, so it is
    /// reported rather than quietly turning an error off.
    @Test func warnsWhenAnotherLanguageIsSetToShowTheSourceScreenshots() throws {
        try makeCleanProject(locales: ["en-US", "de-DE"])
        try FileManager.default.removeItem(
            at: fixture.screenshotsDirectory(locale: "de-DE", deviceClassID: DeviceClass.iPhone69.id)
        )
        try useSourceScreenshots(["de-DE": [DeviceClass.iPhone69.id]])

        let problem = try #require(try fixture.problems().first { $0.locale == "de-DE" && $0.area == .configuration })
        #expect(problem.severity == .warning)
        #expect(problem.kind == .sourceScreenshotsLocaleReadsDifferently)
    }

    // MARK: - Screenshots that are the source language's files

    /// Writes one picture into two languages, which is what a language nobody
    /// translated the screenshots for looks like on disk.
    func writeTheSameScreenshot(
        showing imageName: String,
        at position: Int = 1,
        into locales: [String],
        deviceClass: DeviceClass = .iPhone69
    ) throws {
        let size = deviceClass.acceptedSizes[0]
        for locale in locales {
            // One picture, and the name each language gives it. That is what a
            // language nobody translated the screenshots for looks like.
            try fixture.writeScreenshot(
                locale: locale,
                deviceClassID: deviceClass.id,
                named: screenshotName(
                    imageName, at: position, locale: locale, deviceClass: deviceClass
                ),
                width: size.width,
                height: size.height,
                seed: "one picture for every language"
            )
        }
    }

    @Test func warnsWhenTheScreenshotsAreTheSourceLanguagesFiles() throws {
        try makeCleanProject(locales: ["en-US", "de-DE"])
        try writeTheSameScreenshot(showing: "running-low", into: ["en-US", "de-DE"])

        let problem = try #require(try fixture.problems().first { $0.kind == .screenshotsCopiedFromSource })
        #expect(problem.severity == .warning)
        #expect(problem.locale == "de-DE")
        #expect(problem.fix?.english.contains("1 of 1") == true)
    }

    /// The count is in the fix, so translating one picture does not rewrite the
    /// message and throw away the silence somebody put on it.
    @Test func countsTheScreenshotsThatAreTheSourceLanguagesFiles() throws {
        try makeCleanProject(locales: ["en-US", "de-DE"])
        let size = DeviceClass.iPhone69.acceptedSizes[0]
        for locale in ["en-US", "de-DE"] {
            try fixture.writeScreenshot(
                locale: locale,
                deviceClassID: DeviceClass.iPhone69.id,
                named: screenshotName("shared", at: 2, locale: locale),
                width: size.width,
                height: size.height
            )
        }
        try writeTheSameScreenshot(showing: "running-low", into: ["en-US", "de-DE"])

        let problem = try #require(try fixture.problems().first { $0.kind == .screenshotsCopiedFromSource })
        #expect(problem.fix?.english.contains("1 of 2") == true)
    }

    /// An empty folder and a folder of copies are two rules, and neither is
    /// allowed to speak here.
    static let untranslatedPictureKinds: Set<Problem.Kind> = [
        .screenshotsNotTranslated, .screenshotsCopiedFromSource
    ]

    @Test func saysNothingWhenALanguageHasScreenshotsOfItsOwn() throws {
        try makeCleanProject(locales: ["en-US", "de-DE"])

        #expect(try fixture.problems().contains { Self.untranslatedPictureKinds.contains($0.kind) } == false)
    }

    /// `en-GB` reads the same words as `en-US`, so the same picture in both is
    /// the answer rather than the problem.
    @Test func saysNothingWhenALanguageThatSharesTheBaseHasTheSameFiles() throws {
        try makeCleanProject(locales: ["en-US", "en-GB"])
        try writeTheSameScreenshot(showing: "running-low", into: ["en-US", "en-GB"])

        #expect(try fixture.problems().contains { Self.untranslatedPictureKinds.contains($0.kind) } == false)
    }

    // MARK: - Text taken from the source language

    @Test func warnsForEachUntranslatedTextField() throws {
        try makeCleanProject(locales: ["en-US", "de-DE"])
        let source = goodFields()
        var translation = source
        translation.name = "Translated name"
        try fixture.writeCopy(AppInformation(
            locale: "de-DE",
            status: .approved,
            fields: translation
        ))

        let fields = try fixture.problems()
            .filter { $0.locale == "de-DE" && $0.kind == .textMatchesSource }
            .compactMap(\.field)
        #expect(Set(fields) == [.subtitle, .keywords, .description, .whatsNew])
    }

    @Test func doesNotWarnForSharedWebAddresses() throws {
        try makeCleanProject(locales: ["en-US", "de-DE"])
        let source = goodFields()
        var translation = source
        translation.description = "German description."
        try fixture.writeCopy(AppInformation(
            locale: "de-DE",
            status: .approved,
            fields: translation
        ))

        let fields = try fixture.problems()
            .filter { $0.locale == "de-DE" && $0.kind == .textMatchesSource }
            .compactMap(\.field)
        #expect(Set(fields) == [.name, .subtitle, .keywords, .whatsNew])
    }

    /// `en-GB` and `en-US` are one language. A British listing that keeps the
    /// American words has nothing wrong with it.
    @Test func saysNothingWhenALanguageThatSharesTheBaseKeepsTheSourceWords() throws {
        try makeCleanProject(locales: ["en-US", "en-GB"])
        try fixture.writeCopy(AppInformation(
            locale: "en-GB",
            status: .approved,
            fields: goodFields()
        ))

        #expect(try fixture.problems().contains { $0.kind == .textMatchesSource } == false)
    }
}

/// The name a screenshot in this slot carries. Outside the tests because every
/// fixture in this file needs it, and a name written any other way is itself a
/// warning the validator reports.
private func screenshotName(
    _ imageName: String,
    at position: Int = 1,
    locale: String,
    deviceClass: DeviceClass = .iPhone69
) -> String {
    ScreenshotNaming.fileName(
        position: position,
        imageName: imageName,
        deviceClass: deviceClass,
        locale: locale,
        extension: "png"
    )
}
