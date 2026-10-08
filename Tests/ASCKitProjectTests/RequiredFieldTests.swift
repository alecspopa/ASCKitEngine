import Foundation
import Testing
@testable import ASCKitProject

/// What App Store Connect refuses a submission without. Getting this wrong
/// means finding out at submission time, which is the slowest way to learn
/// that a support URL is missing.
struct RequiredFieldTests {
    let validator = Validator(config: ProjectConfig(
        bundleID: "com.example.Demo",
        keyID: "ABC123",
        sourceLocale: "en-US",
        locales: ["en-US", "de-DE"]
    ))

    /// Everything a published language must carry.
    func complete() -> AppInformation.Fields {
        AppInformation.Fields(
            name: "Demo",
            keywords: "household,restock",
            description: "Know what you have.",
            supportUrl: "https://example.com/support",
            privacyPolicyUrl: "https://example.com/privacy"
        )
    }

    func problems(
        _ fields: AppInformation.Fields,
        locale: String = "en-US",
        source: AppInformation.Fields? = nil
    ) -> [Problem] {
        validator.validateRequiredFields(
            AppInformation(locale: locale, status: .approved, fields: fields),
            locale: locale,
            path: "copy/\(locale).json",
            source: source.map { AppInformation(locale: "en-US", status: .approved, fields: $0) }
        )
    }

    // MARK: - What Apple marks required

    @Test(arguments: [MetadataField.name, .description, .keywords, .supportUrl])
    func refusesToPublishWithoutAFieldAppleRequires(field: MetadataField) {
        var fields = complete()
        fields[field] = nil

        let problem = problems(fields).first { $0.field == field }
        #expect(problem?.severity == .error)
        #expect(problem?.message.english == "en-US has no \(field.rawValue).")
    }

    @Test(arguments: [MetadataField.subtitle, .promotionalText, .marketingUrl])
    func saysNothingAboutAFieldAppleTreatsAsOptional(field: MetadataField) {
        var fields = complete()
        fields[field] = nil
        #expect(problems(fields).contains { $0.field == field } == false)
    }

    @Test func findsNothingWrongWithACompleteLanguage() {
        #expect(problems(complete()).contains { $0.severity == .error } == false)
    }

    // MARK: - The privacy policy

    /// Apple requires it, and it lives on the app information rather than on
    /// the version, so one setting covers the app.
    @Test func requiresThePrivacyPolicyOnTheSourceLanguage() {
        var fields = complete()
        fields.privacyPolicyUrl = nil

        let problem = problems(fields).first { $0.field == .privacyPolicyUrl }
        #expect(problem?.severity == .error)
    }

    @Test func doesNotAskEveryTranslationForItsOwnPrivacyPolicy() {
        var fields = complete()
        fields.privacyPolicyUrl = nil
        #expect(problems(fields, locale: "de-DE").contains { $0.field == .privacyPolicyUrl } == false)
    }

    // MARK: - What's New

    /// Apple needs it for every version except the app's first, and nothing on
    /// disk says which version is the first, so it can only be a warning.
    @Test func warnsAboutWhatsNewRatherThanRefusing() {
        let problem = problems(complete()).first { $0.field == .whatsNew }
        #expect(problem?.severity == .warning)
        #expect(problem?.fix?.english.contains("except the app's first") == true)
    }

    @Test func saysNothingWhenWhatsNewIsThere() {
        var fields = complete()
        fields.whatsNew = "First release."
        #expect(problems(fields).contains { $0.field == .whatsNew } == false)
    }

    // MARK: - Empty is the same as missing

    /// A field set to spaces is not a filled-in field, and writing it would
    /// blank the store rather than satisfy Apple.
    @Test func treatsAFieldOfSpacesAsMissing() {
        var fields = complete()
        fields.supportUrl = "   "
        #expect(problems(fields).contains { $0.field == .supportUrl && $0.severity == .error })
    }

    // MARK: - Where each field is written

    /// Writing one of these to the wrong resource is a 409, not a bad value.
    @Test func knowsThePrivacyPolicyIsAppInformationAndTheSupportURLIsNot() {
        #expect(MetadataField.privacyPolicyUrl.isAppInfoField)
        #expect(MetadataField.supportUrl.isAppInfoField == false)
        #expect(MetadataField.marketingUrl.isAppInfoField == false)
    }

    @Test func treatsEveryWebAddressFieldAsAURL() {
        #expect(MetadataField.privacyPolicyUrl.isURL)
        #expect(MetadataField.supportUrl.isURL)
        #expect(MetadataField.marketingUrl.isURL)
        #expect(MetadataField.description.isURL == false)
    }
}
