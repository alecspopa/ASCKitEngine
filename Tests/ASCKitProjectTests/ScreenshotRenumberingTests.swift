import Foundation
import Testing
@testable import ASCKitProject

/// Reordering means renaming, because the file name is what decides the order.
final class ScreenshotRenumberingTests {
    let fixture: FixtureProject

    init() throws {
        fixture = try FixtureProject()
    }

    deinit {
        fixture.remove()
    }

    var directory: URL {
        fixture.screenshotsDirectory(locale: "en-US", deviceClassID: "iphone-6.9")
    }

    func write(_ names: [String]) throws {
        for name in names {
            try fixture.writeScreenshot(
                locale: "en-US", deviceClassID: "iphone-6.9",
                named: name, width: 1320, height: 2868
            )
        }
    }

    func onDisk() throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .filter { $0.hasSuffix(".png") }
            .sorted()
    }

    // MARK: - Reading a name

    @Test(arguments: [
        ("01-running-low.png", "running-low"),
        ("02-shared.png", "shared"),
        ("10-tags.png", "tags"),
        ("01-one-two-three.png", "one-two-three")
    ])
    func takesTheSlugFromAfterTheNumber(fileName: String, slug: String) {
        #expect(ScreenshotRenumbering.nameWithoutNumber(of: fileName) == slug)
    }

    /// A name with no number keeps all of itself, because there is no number to
    /// strip and guessing would lose part of the slug.
    @Test(arguments: ["running-low.png", "shared.png"])
    func keepsTheWholeNameWhenThereIsNoNumber(fileName: String) {
        #expect(ScreenshotRenumbering.nameWithoutNumber(of: fileName)
            == (fileName as NSString).deletingPathExtension)
    }

    @Test func padsTheNumberSoTenSortsAfterNine() {
        #expect(ScreenshotRenumbering.fileName(position: 1, nameWithoutNumber: "low", extension: "png")
            == "01-low.png")
        #expect(ScreenshotRenumbering.fileName(position: 10, nameWithoutNumber: "low", extension: "png")
            == "10-low.png")
    }

    // MARK: - Working out what moves

    @Test func renamesNothingWhenTheOrderIsAlreadyRight() throws {
        try write(["01-low.png", "02-shared.png"])
        let urls = ["01-low.png", "02-shared.png"].map { directory.appending(path: $0) }

        #expect(ScreenshotRenumbering.plan(for: urls).isEmpty)
    }

    @Test func renamesOnlyTheFilesThatMove() throws {
        try write(["01-low.png", "02-shared.png", "03-tags.png"])
        let urls = ["01-low.png", "03-tags.png", "02-shared.png"]
            .map { directory.appending(path: $0) }

        let moves = ScreenshotRenumbering.plan(for: urls)
        #expect(moves.count == 2, "the first one is already in the right place")
        #expect(moves.map(\.to.lastPathComponent).sorted() == ["02-tags.png", "03-shared.png"])
    }

    // MARK: - Doing it

    /// The slug says what the screenshot shows, so it travels with the image
    /// rather than staying with the number.
    @Test func swapsTwoImagesAndKeepsTheirSlugs() throws {
        try write(["01-low.png", "02-shared.png"])
        let urls = ["02-shared.png", "01-low.png"].map { directory.appending(path: $0) }

        try ScreenshotRenumbering.apply(orderedURLs: urls)

        #expect(try onDisk() == ["01-shared.png", "02-low.png"])
    }

    /// Renaming in place would have 02 land on a name 01 has not left yet.
    @Test func doesNotLoseAFileToACollisionMidRename() throws {
        try write(["01-a.png", "02-b.png", "03-c.png"])
        let urls = ["03-c.png", "01-a.png", "02-b.png"].map { directory.appending(path: $0) }

        try ScreenshotRenumbering.apply(orderedURLs: urls)

        #expect(try onDisk() == ["01-c.png", "02-a.png", "03-b.png"])
        #expect(try onDisk().count == 3, "nothing was overwritten")
    }

    @Test func leavesNoTemporaryFilesBehind() throws {
        try write(["01-a.png", "02-b.png"])
        let urls = ["02-b.png", "01-a.png"].map { directory.appending(path: $0) }

        try ScreenshotRenumbering.apply(orderedURLs: urls)

        let everything = try FileManager.default.contentsOfDirectory(atPath: directory.path)
        #expect(everything.contains { $0.contains("asckit-moving") } == false)
    }

    @Test func numbersFilesThatNeverHadNumbers() throws {
        try write(["shared.png", "low.png"])
        let urls = ["low.png", "shared.png"].map { directory.appending(path: $0) }

        try ScreenshotRenumbering.apply(orderedURLs: urls)

        #expect(try onDisk() == ["01-low.png", "02-shared.png"])
    }
}
