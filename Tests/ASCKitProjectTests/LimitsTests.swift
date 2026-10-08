import Foundation
import Testing
@testable import ASCKitProject

struct LimitsTests {
    /// The one that catches people out, in the other direction. Counting
    /// keywords in UTF-8 bytes blocks Japanese and Chinese fields that App
    /// Store Connect accepts.
    @Test func countsEveryFieldInCharacters() {
        for field in MetadataField.allCases {
            #expect(field.length(of: "家家家") == 3, "\(field.rawValue) should count characters")
        }
    }

    @Test func acceptsEightySixJapaneseKeywordCharacters() {
        let keywords = String(repeating: "家", count: 86)
        #expect(keywords.utf8.count == 258, "the same string is far over 100 bytes")
        #expect(MetadataField.keywords.length(of: keywords) == 86)
        #expect(MetadataField.keywords.length(of: keywords) < MetadataField.keywords.maximumLength!)
    }

    @Test func refusesAHundredAndOneKeywordCharacters() {
        let keywords = String(repeating: "家", count: 101)
        #expect(MetadataField.keywords.length(of: keywords) > MetadataField.keywords.maximumLength!)
    }

    @Test func countsAccentedGermanKeywordsAsOneCharacterEach() {
        let keywords = String(repeating: "ü", count: 60)
        #expect(MetadataField.keywords.length(of: keywords) == 60)
    }

    /// An emoji is several bytes and several scalars, but one character. The
    /// count has to agree with what Apple shows.
    @Test func countsAnEmojiAsOneCharacter() {
        #expect(MetadataField.subtitle.length(of: "Hi 👨‍👩‍👧‍👦") == 4)
    }

    @Test func countsACombiningMarkAsOneCharacter() {
        #expect(MetadataField.name.length(of: "e\u{0301}") == 1)
    }

    @Test(arguments: [
        (MetadataField.name, 30), (.subtitle, 30), (.keywords, 100),
        (.promotionalText, 170), (.description, 4000), (.whatsNew, 4000)
    ])
    func carriesApplesLimits(field: MetadataField, limit: Int) {
        #expect(field.maximumLength == limit)
    }

    @Test func onlyTheNameHasAMinimum() {
        #expect(MetadataField.name.minimumLength == 2)
        for field in MetadataField.allCases where field != .name {
            #expect(field.minimumLength == nil)
        }
    }

    /// Name and subtitle are written to a different resource from the rest, and
    /// getting that wrong means a 409 rather than a bad value.
    @Test func knowsWhichFieldsLiveOnTheAppInformation() {
        #expect(MetadataField.name.isAppInfoField)
        #expect(MetadataField.subtitle.isAppInfoField)
        #expect(MetadataField.supportUrl.isAppInfoField == false)
        #expect(MetadataField.description.isAppInfoField == false)
    }
}

struct StoreLocaleTests {
    /// Apple's codes are not consistent, and a wrong one is skipped silently
    /// rather than refused, so a run looks fine and uploads nothing.
    @Test(arguments: ["en-US", "en-GB", "de-DE", "fr-FR", "it", "nl-NL",
                      "es-ES", "es-MX", "ja", "zh-Hans", "zh-Hant"])
    func acceptsTheCodesAppStoreConnectUses(code: String) {
        #expect(StoreLocale.isKnown(code))
    }

    @Test(arguments: ["ja-JP", "it-IT", "nl", "de", "zh", "zh-CN", "en"])
    func refusesTheCodesPeopleGuess(code: String) {
        #expect(StoreLocale.isKnown(code) == false)
    }

    @Test(arguments: [("ja-JP", "ja"), ("it-IT", "it"), ("nl", "nl-NL"), ("de", "de-DE")])
    func suggestsTheCodeThatWasProbablyMeant(wrong: String, right: String) {
        #expect(StoreLocale.suggestion(for: wrong) == right)
    }

    /// English and Spanish have several storefronts, so there is no single
    /// answer and guessing one would be worse than saying nothing.
    @Test(arguments: ["en", "es", "pt", "fr"])
    func suggestsNothingWhenSeveralCodesWouldFit(code: String) {
        #expect(StoreLocale.suggestion(for: code) == nil)
    }

    @Test func suggestsNothingForACodeThatIsAlreadyRight() {
        #expect(StoreLocale.suggestion(for: "de-DE") == nil)
    }
}

struct DeviceClassTests {
    /// Apple never added an enum value for these two sizes. They widened what
    /// the old identifiers accept instead.
    @Test func mapsTheRequiredSizesOntoApplesOlderIdentifiers() {
        #expect(DeviceClass.iPhone69.displayType.rawValue == "APP_IPHONE_67")
        #expect(DeviceClass.iPad13.displayType.rawValue == "APP_IPAD_PRO_3GEN_129")
    }

    @Test func acceptsTheNativeSizeOfTheDevicesTheseScreensComeFrom() {
        #expect(DeviceClass.iPhone69.accepts(width: 1320, height: 2868))
        #expect(DeviceClass.iPad13.accepts(width: 2064, height: 2752))
    }

    @Test func acceptsLandscapeAsThePortraitSizeSwapped() {
        #expect(DeviceClass.iPhone69.accepts(width: 2868, height: 1320))
        #expect(DeviceClass.iPad13.accepts(width: 2752, height: 2064))
    }

    /// The iPhone 17 Pro is a 6.3 inch device. Its screenshots are not an
    /// accepted upload size, which is easy to miss because the app runs fine.
    @Test func refusesTheSizeAnIPhone17ProProduces() {
        #expect(DeviceClass.iPhone69.accepts(width: 1206, height: 2622) == false)
    }

    @Test func refusesASizeThatBelongsToAnotherDeviceClass() {
        #expect(DeviceClass.iPhone69.accepts(width: 2064, height: 2752) == false)
        #expect(DeviceClass.iPad13.accepts(width: 1320, height: 2868) == false)
    }

    @Test func looksUpADeviceClassByTheNameUsedInTheConfiguration() {
        #expect(DeviceClass.named("iphone-6.9") == .iPhone69)
        #expect(DeviceClass.named("ipad-13") == .iPad13)
        #expect(DeviceClass.named("iphone-7.2") == nil)
    }
}

/// A thumbnail sized for an iPhone does not suit an iPad, and a landscape
/// screenshot is wider again.
struct DeviceClassShapeTests {
    @Test func knowsAnIPhoneIsTallerThanAnIPad() {
        #expect(DeviceClass.iPhone69.aspectRatio < DeviceClass.iPad13.aspectRatio)
    }

    @Test(arguments: [
        (DeviceClass.iPhone69, 1320.0 / 2868.0),
        (DeviceClass.iPad13, 2064.0 / 2752.0)
    ])
    func takesTheRatioFromTheSizeAppleAccepts(deviceClass: DeviceClass, ratio: Double) {
        #expect(abs(deviceClass.aspectRatio - ratio) < 0.001)
    }

    func file(width: Int, height: Int) -> ScreenshotFile {
        ScreenshotFile(
            url: URL(fileURLWithPath: "/tmp/\(width)x\(height).png"),
            fileName: "\(width)x\(height).png",
            byteCount: 1,
            pixelWidth: width,
            pixelHeight: height,
            hasAlpha: false
        )
    }

    /// An empty folder still needs a column width, and the device's own shape
    /// is the best guess available.
    @Test func fallsBackToTheDevicesOwnShapeWithNoFiles() {
        #expect(DeviceClass.iPad13.widestRatio(among: []) == DeviceClass.iPad13.aspectRatio)
    }

    /// Leaving room for a landscape image that is not there would leave most of
    /// the row empty, and almost every set is upright.
    @Test func measuresTheFilesRatherThanWhatTheDeviceCouldProduce() {
        let upright = [file(width: 1320, height: 2868), file(width: 1320, height: 2868)]
        let ratio = DeviceClass.iPhone69.widestRatio(among: upright)

        #expect(abs(ratio - 1320.0 / 2868.0) < 0.001)
        #expect(ratio < 1, "nothing here is wider than it is tall")
    }

    /// One landscape image in a set widens the whole row, because the row has
    /// to hold it.
    @Test func widensForALandscapeImageThatIsActuallyThere() {
        let mixed = [file(width: 1320, height: 2868), file(width: 2868, height: 1320)]
        let ratio = DeviceClass.iPhone69.widestRatio(among: mixed)

        #expect(abs(ratio - 2868.0 / 1320.0) < 0.001)
        #expect(ratio > 1)
    }

    @Test func ignoresAFileItCouldNotMeasure() {
        let unreadable = ScreenshotFile(
            url: URL(fileURLWithPath: "/tmp/broken.png"),
            fileName: "broken.png",
            byteCount: 0,
            pixelWidth: nil,
            pixelHeight: nil,
            hasAlpha: nil
        )
        let ratio = DeviceClass.iPad13.widestRatio(among: [unreadable])
        #expect(ratio == DeviceClass.iPad13.aspectRatio)
    }
}
