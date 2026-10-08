import ASCKitAPI
import Foundation
import Testing
@testable import ASCKitProject

/// The words the publish sheet shows after a push. A push names every language
/// it touched, so what is tested here is the shape that keeps it readable: a
/// heading, then one indented line per language.
struct PushOutcomeTextTests {
    /// Adoption carries the configuration it wrote. None of the wording reads
    /// it, so any configuration will do.
    let config = ProjectConfig(bundleID: "com.example.MyApp", keyID: "ABC123")

    // MARK: - Taking the store's purchases into files

    @Test func adoptedProductsAreListedUnderWhatHappenedToThem() {
        let outcome = ProductSnapshot.Outcome(
            written: ["com.example.pro", "com.example.tips"],
            left: ["com.example.old"],
            refused: []
        )

        #expect(PushOutcomeText.describe(outcome) == """
        Written:
          com.example.pro
          com.example.tips

        Left alone, already there:
          com.example.old
        """)
    }

    /// A refusal carries its own reason, so it gets a line rather than a place
    /// under a heading.
    @Test func aRefusedProductSaysWhyOnItsOwnLine() {
        let outcome = ProductSnapshot.Outcome(
            written: [],
            left: [],
            refused: [(productID: "a/b", reason: "A product id cannot hold a slash.")]
        )

        #expect(PushOutcomeText.describe(outcome) == "Skipped a/b. A product id cannot hold a slash.")
    }

    @Test func adoptingNothingSaysSo() {
        let outcome = ProductSnapshot.Outcome(written: [], left: [], refused: [])
        #expect(PushOutcomeText.describe(outcome) == "Nothing to write.")
    }

    // MARK: - Screenshots

    @Test func screenshotsGroupTheDeviceClassesOfOneLanguage() {
        var result = ScreenshotPusher.Result()
        result.uploaded = [
            "de-DE|iphone-6.9", "de-DE|ipad-13",
            "en-US|iphone-6.9", "en-US|ipad-13",
            "es-ES|iphone-6.9"
        ]

        #expect(PushOutcomeText.describe(result) == """
        Overwritten:
          de-DE: iphone-6.9, ipad-13
          en-US: iphone-6.9, ipad-13
          es-ES: iphone-6.9
        """)
    }

    /// Languages stay in the order they went up in, so the list reads the same
    /// way the push ran.
    @Test func screenshotsKeepTheOrderTheyWentUpIn() {
        var result = ScreenshotPusher.Result()
        result.uploaded = ["es-ES|iphone-6.9", "de-DE|iphone-6.9", "en-US|iphone-6.9"]

        let locales = PushOutcomeText.describe(result)
            .split(separator: "\n")
            .dropFirst()
            .map { $0.trimmingCharacters(in: .whitespaces) }

        #expect(locales == ["es-ES: iphone-6.9", "de-DE: iphone-6.9", "en-US: iphone-6.9"])
    }

    @Test func archivedAssetsGetTheirOwnSection() {
        var result = ScreenshotPusher.Result()
        result.uploaded = ["de-DE|iphone-6.9"]
        result.archived = [
            RemoteLibraryAsset(id: "a1", media: .image, fileName: "01.png", referenceName: "de-DE 01.png"),
            RemoteLibraryAsset(id: "a2", media: .image, fileName: "02.png")
        ]

        #expect(PushOutcomeText.describe(result) == """
        Overwritten:
          de-DE: iphone-6.9

        Archived in the library, because nothing shows them any more:
          de-DE 01.png
          02.png
        """)
    }

    @Test func failedScreenshotsGetTheirOwnSection() {
        var result = ScreenshotPusher.Result()
        result.uploaded = ["de-DE|iphone-6.9"]
        result.failed = [
            .init(locale: "en-US", deviceClassID: "ipad-13", message: "The file was too large")
        ]

        #expect(PushOutcomeText.describe(result) == """
        Overwritten:
          de-DE: iphone-6.9

        Failed:
          en-US, ipad-13: The file was too large
        """)
    }

    @Test func aScreenshotPushThatDidNothingSaysSo() {
        #expect(PushOutcomeText.describe(ScreenshotPusher.Result()) == "Nothing to upload.")
    }

    // MARK: - Text

    @Test func textListsOneLanguagePerLine() {
        var result = TextPusher.Result()
        result.written = ["en-US", "de-DE"]

        #expect(PushOutcomeText.describe(result) == """
        Written:
          en-US
          de-DE
        """)
    }

    /// A refusal is one field of one language. The rest of that language went,
    /// and the line says so, because otherwise it reads as a lost push.
    @Test func aRefusedFieldSaysTheRestOfThatLanguageWent() {
        var result = TextPusher.Result()
        result.written = ["en-US"]
        result.refused = [
            .init(locale: "en-US", field: .whatsNew, reason: "Not on a first version")
        ]

        #expect(PushOutcomeText.describe(result) == """
        Written:
          en-US

        Refused in this state:
          en-US, whatsNew. The rest of en-US went.
        """)
    }

    @Test func aRefusedFieldOfALanguageThatWroteNothingSaysNothingMore() {
        var result = TextPusher.Result()
        result.refused = [
            .init(locale: "de-DE", field: .whatsNew, reason: "Not on a first version")
        ]

        #expect(PushOutcomeText.describe(result) == """
        Refused in this state:
          de-DE, whatsNew.
        """)
    }

    @Test func failedTextGetsItsOwnSection() {
        var result = TextPusher.Result()
        result.failed = [.init(locale: "fr-FR", message: "The description is too long")]

        #expect(PushOutcomeText.describe(result) == """
        Failed:
          fr-FR: The description is too long
        """)
    }

    @Test func aTextPushThatDidNothingSaysSo() {
        #expect(PushOutcomeText.describe(TextPusher.Result()) == "Nothing to write.")
    }

    // MARK: - The record of the push

    @Test func theRecordGoesUnderWhatThePushDid() {
        var result = TextPusher.Result()
        result.written = ["en-US"]
        let outcome = PushSession.Outcome(
            result: result,
            receiptURL: URL(filePath: "/tmp/history/2026-08-29-text.json"),
            receiptFailure: nil
        )

        #expect(PushOutcomeText.describe(outcome) == """
        Written:
          en-US

        Recorded in 2026-08-29-text.json
        """)
    }

    /// A push that worked must not read as failed because the note about it
    /// could not be filed.
    @Test func aRecordThatCouldNotBeWrittenSaysThePushStillWent() {
        var result = TextPusher.Result()
        result.written = ["en-US"]
        let outcome = PushSession.Outcome(
            result: result,
            receiptURL: nil,
            receiptFailure: "The history folder is read only"
        )

        #expect(PushOutcomeText.describe(outcome) == """
        Written:
          en-US

        The push went. The record of it could not be written: The history folder is read only
        """)
    }

    // MARK: - Reading and adopting

    @Test func aSnapshotSplitsWhatItWroteFromWhatItLeft() {
        var outcome = SnapshotWriter.Outcome()
        outcome.written = ["en-US"]
        outcome.skipped = ["de-DE", "es-ES"]

        #expect(PushOutcomeText.describe(outcome) == """
        Written:
          en-US

        Left alone, already there:
          de-DE
          es-ES
        """)
    }

    @Test func aFillNamesTheFieldsItFilled() {
        var outcome = SnapshotWriter.FillOutcome()
        outcome.filled = ["en-US": [.subtitle], "de-DE": [.description, .whatsNew]]

        #expect(PushOutcomeText.describe(outcome) == """
        Filled from App Store Connect:
          de-DE: Description, What's New
          en-US: Subtitle
        """)
    }

    @Test func aFillThatDidNothingSaysSo() {
        #expect(PushOutcomeText.describe(SnapshotWriter.FillOutcome()) == "Nothing to fill.")
    }

    @Test func adoptionNamesEachThingItDid() {
        let outcome = LocaleAdoption.Outcome(
            added: ["fr-FR"],
            written: ["fr-FR"],
            left: ["en-US"],
            version: "1.0",
            config: config
        )

        #expect(PushOutcomeText.describe(outcome) == """
        Added:
          fr-FR

        App information file written for:
          fr-FR

        Left alone, already there:
          en-US
        """)
    }

    @Test func anAdoptionThatDidNothingSaysSo() {
        let outcome = LocaleAdoption.Outcome(version: "1.0", config: config)
        #expect(PushOutcomeText.describe(outcome) == "Nothing to add.")
    }

    // MARK: - Several parts in one press

    @Test func everyPartOfOnePushIsUnderItsOwnHeading() {
        let report = PushOutcomeText.joined([
            (part: .appInformation, outcome: "Written:\n  en-US"),
            (part: .screenshots, outcome: "Overwritten:\n  ro: iPhone 6.9\"")
        ])

        #expect(report == """
        App Information:
          Written:
            en-US

        Screenshots:
          Overwritten:
            ro: iPhone 6.9"
        """)
    }

    /// The receipt line is the only record of where the push went, so joining
    /// two reports must not swallow it.
    @Test func joiningKeepsTheReceiptLineOfEachPart() {
        let report = PushOutcomeText.joined([
            (part: .purchases, outcome: "Written:\n  com.example.pro\n\nRecorded in words.json"),
            (part: .prices, outcome: "Written: 2 prices.\n\nRecorded in prices.json")
        ])

        #expect(report == """
        In-App Purchases:
          Written:
            com.example.pro

          Recorded in words.json

        Prices:
          Written: 2 prices.

          Recorded in prices.json
        """)
    }

    /// One button writes up to four things, so even one of them has to say
    /// which one it was.
    @Test func onePartStillCarriesItsHeading() {
        let report = PushOutcomeText.joined([(part: .prices, outcome: "Nothing to write.")])
        #expect(report == """
        Prices:
          Nothing to write.
        """)
    }

    @Test func joiningNothingSaysSo() {
        #expect(PushOutcomeText.joined([]) == "Nothing to write.")
    }

    // MARK: - Copies made after pictures were filed

    /// Nobody pressed anything to make these, so each one is named and the
    /// Trash is said out loud.
    @Test func aCopyMadeAfterFilingNamesTheSetAndTheTrash() {
        let copies = [SiblingScreenshots.Remembered(
            locale: "es-ES", from: "es-MX", deviceClass: .iPad13, count: 6, trashed: 5
        )]

        #expect(PushOutcomeText.describe(copies) == """
        Screenshots copied from another language, as copiesScreenshotsFrom says:
          es-ES, iPad 13 inch, from es-MX

        The files that were there are in the Trash.
        """)
    }

    @Test func aCopyIntoAnEmptySetSaysNothingAboutTheTrash() {
        let copies = [SiblingScreenshots.Remembered(
            locale: "es-ES", from: "es-MX", deviceClass: .iPad13, count: 6, trashed: 0
        )]

        #expect(PushOutcomeText.describe(copies).contains("Trash") == false)
    }

    @Test func noCopyIsNoText() {
        #expect(PushOutcomeText.describe([SiblingScreenshots.Remembered]()).isEmpty)
    }
}
