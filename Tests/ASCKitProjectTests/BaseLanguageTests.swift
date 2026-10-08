import Testing
@testable import ASCKitProject

/// Which languages read the same words, which is what decides whether one can
/// show another's screenshots.
struct BaseLanguageTests {
    @Test func readsTheLanguageOutOfARegionCode() {
        #expect(StoreLocale.baseLanguage(of: "en-US") == "en")
        #expect(StoreLocale.baseLanguage(of: "en-GB") == "en")
        #expect(StoreLocale.baseLanguage(of: "pt-BR") == "pt")
    }

    @Test func leavesACodeWithNoRegionAlone() {
        #expect(StoreLocale.baseLanguage(of: "ja") == "ja")
        #expect(StoreLocale.baseLanguage(of: "ro") == "ro")
    }

    /// A script is not a region. Simplified and Traditional Chinese are written
    /// differently, so a picture of one is not a picture of the other.
    @Test func keepsAScriptAndTellsTheTwoChineseApart() {
        #expect(StoreLocale.baseLanguage(of: "zh-Hans") == "zh-Hans")
        #expect(StoreLocale.baseLanguage(of: "zh-Hant") == "zh-Hant")
        #expect(StoreLocale.baseLanguage(of: "zh-Hans") != StoreLocale.baseLanguage(of: "zh-Hant"))
    }

    @Test func answersAnUnknownCodeWithItself() {
        #expect(StoreLocale.baseLanguage(of: "klingon") == "klingon")
    }

    @Test func everyEnglishListingSharesAnEnglishSource() {
        let config = ProjectConfig(bundleID: "com.example.MyApp", keyID: "ABC123")
        #expect(config.sourceLocale == "en-US")
        #expect(config.sharesSourceLanguage("en-GB"))
        #expect(config.sharesSourceLanguage("en-AU"))
        #expect(config.sharesSourceLanguage("de-DE") == false)
        #expect(config.sharesSourceLanguage("es-MX") == false)
    }

    /// The source language shares its own base, so every caller needs its own
    /// guard rather than reading this as "another language like this one".
    @Test func answersTrueForTheSourceLanguageItself() {
        let config = ProjectConfig(bundleID: "com.example.MyApp", keyID: "ABC123")
        #expect(config.sharesSourceLanguage("en-US"))
    }

    // MARK: - Words a language took from the source language

    /// The one rule the listing and the in-app purchases both ask.
    @Test func warnsAboutCopiedTextInALanguageThatReadsOtherWords() {
        let config = ProjectConfig(bundleID: "com.example.MyApp", keyID: "ABC123")

        #expect(config.warnsAboutCopiedText(MetadataField.description, in: "de-DE"))
        #expect(config.warnsAboutCopiedText(ProductField.name, in: "de-DE"))
        #expect(config.warnsAboutCopiedText(ProductField.description, in: "ro"))
    }

    @Test func saysNothingAboutCopiedTextInALanguageThatSharesTheBase() {
        let config = ProjectConfig(bundleID: "com.example.MyApp", keyID: "ABC123")

        #expect(config.warnsAboutCopiedText(MetadataField.description, in: "en-GB") == false)
        #expect(config.warnsAboutCopiedText(ProductField.name, in: "en-GB") == false)
        #expect(config.warnsAboutCopiedText(ProductField.name, in: "en-US") == false)
    }

    /// A web address is the same address in every language.
    @Test func saysNothingAboutAWebAddressAnyLanguageCopied() {
        let config = ProjectConfig(bundleID: "com.example.MyApp", keyID: "ABC123")

        #expect(config.warnsAboutCopiedText(MetadataField.supportUrl, in: "de-DE") == false)
        #expect(config.warnsAboutCopiedText(MetadataField.marketingUrl, in: "de-DE") == false)
        #expect(config.warnsAboutCopiedText(MetadataField.privacyPolicyUrl, in: "de-DE") == false)
    }
}
