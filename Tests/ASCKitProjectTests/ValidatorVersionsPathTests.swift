import Foundation
import Testing
@testable import ASCKitProject

struct ValidatorVersionsPathTests {
    @Test func namesPreviewAndCreativeProblemsUnderTheConfiguredFolder() {
        let config = ProjectConfig(
            bundleID: "b", keyID: "K", issuerID: "I", locales: ["en-US"],
            deviceClasses: [DeviceClass.iPhone69.id], versionsPath: "releases"
        )
        var previews = PreviewFolder()
        previews.previews[ScreenshotSlot(locale: "en-US", deviceClassID: DeviceClass.iPhone69.id)] = [
            ValidatorPreviewTests.preview("01-a.avi", readable: false)
        ]
        let content = VersionContent(
            versionString: "1.0", appInformation: [:], unreadableInformation: [:], screenshots: [:], screenshotLocales: [],
            previewFolder: previews, creativeFolder: Art.folder([:], strays: ["banner.png"])
        )
        let validator = Validator(config: config)

        let preview = validator.validatePreviews(content)
        let creative = validator.validateCreative(content)

        #expect(preview.isEmpty == false)
        #expect(creative.isEmpty == false)
        #expect((preview + creative).allSatisfy { $0.path?.hasPrefix("releases/1.0/") == true })
    }
}
