import Foundation
import Testing
@testable import ASCKitProject

/// The file name is the whole instruction a person gives, and the app and the
/// command line tool both act on it, so what it says has to be beyond doubt.
struct ScreenshotNamingTests {
    /// Two languages and two device classes, which is what most projects look
    /// like and what the refusals have to name.
    let config = ProjectConfig(
        bundleID: "com.example.Demo",
        keyID: "ABC123",
        sourceLocale: "en-US",
        locales: ["en-US", "de-DE"],
        deviceClasses: [DeviceClass.iPhone69.id, DeviceClass.iPad13.id]
    )

    func read(_ fileName: String, config: ProjectConfig? = nil) -> Result<
        ScreenshotNaming.Parts, ScreenshotNaming.Refusal
    > {
        ScreenshotNaming.read(fileName, config: config ?? self.config)
    }

    // MARK: - A name that says everything

    @Test func readsTheLanguageTheDeviceAndTheName() throws {
        let parts = try read("03-shopping-iPhone-6.9-en_US.png").get()

        #expect(parts.locale == "en-US")
        #expect(parts.deviceClass == .iPhone69)
        #expect(parts.imageName == "shopping")
    }

    /// The name of the thing on screen can hold hyphens of its own. Everything
    /// between the number and the device class is that name.
    @Test func keepsAHyphenatedName() throws {
        let parts = try read("01-running-low-iPad-13-de_DE.png").get()

        #expect(parts.locale == "de-DE")
        #expect(parts.deviceClass == .iPad13)
        #expect(parts.imageName == "running-low")
    }

    /// A person types what is on their keyboard, and App Store Connect writes
    /// `en-US`. Both mean the same folder.
    @Test func readsACodeTypedInAnyCase() throws {
        #expect(try read("01-hero-iphone-6.9-EN_us.png").get().locale == "en-US")
    }

    /// The pattern uses an underscore so the whole code stays in one piece, and
    /// a hyphen is read the same way for somebody who writes the code the way
    /// App Store Connect prints it.
    @Test func readsACodeWrittenWithAHyphen() throws {
        let parts = try read("01-hero-iPhone-6.9-en-US.png").get()

        #expect(parts.locale == "en-US")
        #expect(parts.imageName == "hero")
    }

    @Test func readsACodeThatCarriesAScriptRatherThanACountry() throws {
        let chinese = ProjectConfig(
            bundleID: "com.example.Demo",
            keyID: "ABC123",
            locales: ["zh-Hans"],
            deviceClasses: [DeviceClass.iPhone69.id]
        )
        #expect(try read("01-hero-iPhone-6.9-zh_Hans.png", config: chinese).get().locale == "zh-Hans")
    }

    /// A number is what puts a set in order, and a file that arrives without
    /// one still has to land somewhere.
    @Test func readsANameWithNoNumberInFrontOfIt() throws {
        #expect(try read("hero-iPhone-6.9-en_US.png").get().imageName == "hero")
    }

    // MARK: - Two letters on their own

    /// `en` is not a code App Store Connect knows, and a project shipping one
    /// English needs no more than that to be understood.
    @Test func readsTwoLettersAsTheOneLanguageTheProjectShipsForThem() throws {
        #expect(try read("01-hero-iPhone-6.9-en.png").get().locale == "en-US")
    }

    /// Two Englishes, and the file says only `en`. Guessing would put the
    /// screenshot in front of the wrong country, so this asks instead.
    @Test func refusesTwoLettersWhenTwoLanguagesFitThem() throws {
        let twoEnglishes = ProjectConfig(
            bundleID: "com.example.Demo",
            keyID: "ABC123",
            locales: ["en-US", "en-GB"],
            deviceClasses: [DeviceClass.iPhone69.id]
        )
        let refusal = try #require(
            read("01-hero-iPhone-6.9-en.png", config: twoEnglishes).failure
        )
        #expect(refusal.description.contains("en-US, en-GB"))
        #expect(refusal.description.contains("en_US"))
    }

    /// `it` is Italian to App Store Connect, so it is Italian here, and a
    /// project that does not ship it is told so rather than left guessing.
    @Test func readsTwoLettersThatAreAStoreCodeOnTheirOwn() throws {
        let italian = ProjectConfig(
            bundleID: "com.example.Demo",
            keyID: "ABC123",
            locales: ["it"],
            deviceClasses: [DeviceClass.iPhone69.id]
        )
        #expect(try read("01-hero-iPhone-6.9-it.png", config: italian).get().locale == "it")
    }

    // MARK: - Names that say too little

    @Test func refusesANameThatEndsWithSomethingThatIsNotALanguage() throws {
        let refusal = try #require(read("01-hero-iPhone-6.9.png").failure)

        #expect(refusal.description.contains("is not a language"))
        #expect(refusal.description.contains(ScreenshotNaming.example))
    }

    @Test func refusesALanguageTheProjectDoesNotShip() throws {
        let refusal = try #require(read("01-hero-iPhone-6.9-ja.png").failure)

        #expect(refusal.description.contains("ja"))
        #expect(refusal.description.contains("en-US, de-DE"))
    }

    @Test func refusesANameThatSaysNoDevice() throws {
        let refusal = try #require(read("01-hero-en_US.png").failure)

        #expect(refusal.description.contains("does not say which device"))
        #expect(refusal.description.contains("iphone-6.9, ipad-13"))
    }

    @Test func refusesADeviceClassTheProjectDoesNotList() throws {
        let refusal = try #require(read("01-hero-iPhone-6.5-en_US.png").failure)

        #expect(refusal.description.contains("iPhone 6.5 inch"))
        #expect(refusal.description.contains("does not list"))
    }

    /// Everything the name says is where the file goes, and nothing is left to
    /// say what is in the picture.
    @Test func refusesANameThatSaysNothingAboutTheScreenshot() throws {
        let refusal = try #require(read("iPhone-6.9-en_US.png").failure)

        #expect(refusal.description.contains("says nothing about"))
    }

    // MARK: - The part that says what the screenshot shows

    /// One screenshot reads the same in every language folder, which is how
    /// German is matched to the English picture beside it.
    @Test func fileNameKeepsOnlyWhatTheScreenshotShows() {
        #expect(ScreenshotNaming.imageName(of: "03-shopping-iPhone-6.9-en_US.png") == "shopping")
        #expect(ScreenshotNaming.imageName(of: "01-running-low-iPad-13-de_DE.png") == "running-low")
    }

    /// A file handed over from outside a project says none of this, and it
    /// still has to be filed under something.
    @Test func fileNameFallsBackToTheNameItCameWith() {
        #expect(ScreenshotNaming.imageName(of: "hero.png") == "hero")
        #expect(ScreenshotNaming.imageName(of: "03-hero.png") == "hero")
    }

    // MARK: - Writing a name

    /// What is written is what `read` takes back, so a file ASCKit named can
    /// always be filed again.
    @Test func writesTheNameItCanReadBack() throws {
        let written = ScreenshotNaming.fileName(
            position: 3,
            imageName: "shopping",
            deviceClass: .iPhone69,
            locale: "en-US",
            extension: "png"
        )

        #expect(written == "03-shopping-iPhone-6.9-en_US.png")

        let parts = try read(written).get()
        #expect(parts.locale == "en-US")
        #expect(parts.deviceClass == .iPhone69)
        #expect(parts.imageName == "shopping")
    }

    /// A language with no country in it says only the language.
    @Test func writesALanguageThatHasNoCountry() {
        #expect(ScreenshotNaming.token(of: "ja") == "ja")
        #expect(ScreenshotNaming.token(of: "de-DE") == "de_DE")
    }

    @Test func writesTheDeviceTheWayAPersonDoes() {
        #expect(DeviceClass.iPhone69.fileNameToken == "iPhone-6.9")
        #expect(DeviceClass.iPad13.fileNameToken == "iPad-13")
    }

    // MARK: - Refusing a name at the door

    @Test func acceptsANameThatSaysThisSlot() {
        #expect(ScreenshotNaming.reasonToRefuse(
            "03-shopping-iPhone-6.9-en_US.png",
            locale: "en-US",
            deviceClass: .iPhone69,
            config: config
        ) == nil)
    }

    @Test func refusesANameThatSaysAnotherLanguage() throws {
        let reason = try #require(ScreenshotNaming.reasonToRefuse(
            "03-shopping-iPhone-6.9-de_DE.png",
            locale: "en-US",
            deviceClass: .iPhone69,
            config: config
        ))

        #expect(reason.contains("de-DE"))
        #expect(reason.contains("en-US"))
    }

    @Test func refusesANameThatSaysAnotherDeviceClass() throws {
        let reason = try #require(ScreenshotNaming.reasonToRefuse(
            "03-shopping-iPad-13-en_US.png",
            locale: "en-US",
            deviceClass: .iPhone69,
            config: config
        ))

        #expect(reason.contains(DeviceClass.iPad13.displayName))
        #expect(reason.contains(DeviceClass.iPhone69.displayName))
    }

    /// The refusal a person reads is the one `read` writes, so the words are
    /// the same wherever a file is turned away.
    @Test func refusesANameThatSaysNothing() throws {
        let reason = try #require(ScreenshotNaming.reasonToRefuse(
            "hero.png",
            locale: "en-US",
            deviceClass: .iPhone69,
            config: config
        ))

        #expect(reason.contains(ScreenshotNaming.example))
    }
}

private extension Result {
    var failure: Failure? {
        guard case let .failure(error) = self else { return nil }
        return error
    }
}
