import Foundation
import Testing
@testable import ASCKitProject

/// `copiesScreenshotsFrom` in the configuration file.
///
/// A new version folder leaves out a copy it cannot make, so an entry that
/// names the wrong thing reads as a set that stays old.
struct ValidatorScreenshotCopyTests {
    func problems(copies: [String: [String: String]]) -> [Problem] {
        let config = ProjectConfig(
            bundleID: "com.example.MyApp",
            keyID: "ABC123",
            issuerID: "issuer",
            locales: ["en-US", "en-GB", "de-DE"],
            deviceClasses: [DeviceClass.iPhone69.id],
            copiesScreenshotsFrom: copies
        )
        return Validator(config: config).validateConfiguration()
            .filter { $0.kind == .screenshotCopyCannotBeMade }
    }

    @Test("A copy that cannot be made is reported", arguments: [
        ["de-DE": [DeviceClass.iPhone69.id: "en-US"]],
        ["en-GB": [DeviceClass.iPhone69.id: "en-AU"]],
        ["en-GB": [DeviceClass.iPad13.id: "en-US"]],
        ["fr-FR": [DeviceClass.iPhone69.id: "fr-CA"]]
    ])
    func reportsACopyThatCannotBeMade(copies: [String: [String: String]]) throws {
        let problem = try #require(problems(copies: copies).first)

        #expect(problem.severity == .warning)
        #expect(problem.area == .configuration)
        #expect(problem.locale == copies.keys.first)
        #expect(problem.deviceClassID == copies.values.first?.keys.first)
    }

    @Test("Two languages that copy each other are both reported")
    func reportsARing() {
        let found = problems(copies: [
            "en-GB": [DeviceClass.iPhone69.id: "en-US"],
            "en-US": [DeviceClass.iPhone69.id: "en-GB"]
        ])

        #expect(found.compactMap(\.locale) == ["en-GB", "en-US"])
    }

    @Test("A copy between two languages of one language is not reported")
    func saysNothingAboutACopyItCanMake() {
        #expect(problems(copies: ["en-GB": [DeviceClass.iPhone69.id: "en-US"]]).isEmpty)
    }
}
