import Foundation
import Testing
@testable import ASCKitProject

struct MediaRulesTests {
    @Test func builtInPreviewRulesKeepApplesNumbers() {
        let rules = VideoRules.builtIn(.iPad13)

        #expect(rules.accepts(width: 1200, height: 1600))
        #expect(rules.frameRates == 1 ... 30)
        #expect(rules.duration == 15 ... 30)
        #expect(rules.maxFileSize == 500 * 1024 * 1024)
        #expect(rules.fileExtensions == [".m4v", ".mov", ".mp4"])
    }

    @Test func builtInCreativeRulesKeepApplesNumbers() {
        let header = CreativeRules.builtIn(.header)
        let search = CreativeRules.builtIn(.searchResults)

        #expect(header.images.first?.size.minWidth == 3840)
        #expect(header.images.first?.fileExtensions == [".jpeg", ".jpg", ".png"])
        #expect(header.images.last?.fileExtensions == [".png"])
        #expect(search.videoSizes.first?.fileExtensions == [".m4v", ".mov", ".mp4"])
        #expect(search.duration == 5 ... 30)
        #expect(search.frameRates == [30, 60])
    }

    @Test func folderNamesComeFromOnePlace() {
        let config = ProjectConfig(bundleID: "com.example.MyApp", keyID: "ABC123", issuerID: "issuer")
        let project = Project(configURL: URL(fileURLWithPath: "/tmp/demo/asckit.json"), config: config)

        #expect(ExperimentContentStore.previewsFolderName == Project.previewsFolderName)
        #expect(project.previewsURL(version: "1.0").lastPathComponent == "previews")
        #expect(project.screenshotsURL(version: "1.0").lastPathComponent == "screenshots")
        #expect(project.cacheURL.lastPathComponent == "cache")
    }
}
