import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
@testable import ASCKitProject

/// Builds a project directory in a temporary folder, so the validator is
/// exercised against real files rather than against a model of them.
struct FixtureProject {
    let rootURL: URL
    let version: String

    /// Fixtures are built under the package's own `.build/test-fixtures`,
    /// not in the system temporary folder. They stay inside the repository
    /// where they can be looked at when a test fails, and `.build` is already
    /// ignored by git so nothing dirties the working tree.
    /// Made once, by `static let`, so parallel tests never race each other
    /// creating the same parent. Each test then makes only its own uniquely
    /// named folder inside it, which nothing else can be making at the time.
    static let fixturesRoot: URL = {
        // #filePath is .../Tests/ASCKitProjectTests/FixtureProject.swift
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: ".build")
            .appending(path: "test-fixtures")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    init(version: String = "1.0") throws {
        self.version = version
        rootURL = Self.fixturesRoot.appending(path: "asckit-fixture-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: false)
    }

    /// Another version inside a project that already exists.
    static func at(_ rootURL: URL, version: String) -> FixtureProject {
        FixtureProject(rootURL: rootURL, version: version)
    }

    private init(rootURL: URL, version: String) {
        self.rootURL = rootURL
        self.version = version
    }

    func remove() {
        try? FileManager.default.removeItem(at: rootURL)
    }

    // MARK: - Writing

    @discardableResult
    func writeConfig(_ config: ProjectConfig) throws -> URL {
        let url = rootURL.appending(path: Project.defaultConfigName)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(config).write(to: url)
        return url
    }

    func writeCopy(_ copy: AppInformation, named fileName: String? = nil) throws {
        let directory = rootURL.appending(path: "versions").appending(path: version).appending(path: Project.informationFolderName)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(copy).write(to: directory.appending(path: fileName ?? "\(copy.locale).json"))
    }

    func writeProduct(_ product: Product, named fileName: String? = nil) throws {
        let directory = rootURL.appending(path: "products")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let name = fileName ?? "\(product.productID).json"
        try encoder.encode(product).write(to: directory.appending(path: name))
    }

    /// A group with a display name in every language the fixtures ship, so a
    /// subscription that names it has nothing to warn about.
    func writeGroup(_ group: SubscriptionGroup = SubscriptionGroup(
        referenceName: "Pro",
        status: .approved,
        localizations: ["en-US": .init(name: "Pro"), "de-DE": .init(name: "Pro")]
    )) throws {
        try ContentWriter.writeSubscriptionGroup(group, in: load())
    }

    func writeRawGroup(_ text: String, named fileName: String) throws {
        let directory = rootURL.appending(path: "products/groups")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(text.utf8).write(to: directory.appending(path: fileName))
    }

    /// For the cases a `Product` cannot express: broken JSON, a key nobody
    /// knows, an amount written as a number.
    func writeRawProduct(_ text: String, named fileName: String) throws {
        let directory = rootURL.appending(path: "products")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(text.utf8).write(to: directory.appending(path: fileName))
    }

    func products() throws -> ProductCatalog {
        try ProductStore.load(in: load())
    }

    func writeRawCopy(_ text: String, locale: String) throws {
        let directory = rootURL.appending(path: "versions").appending(path: version).appending(path: Project.informationFolderName)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data(text.utf8).write(to: directory.appending(path: "\(locale).json"))
    }

    func writeScreenshot(
        locale: String,
        deviceClassID: String,
        named fileName: String,
        width: Int,
        height: Int,
        hasAlpha: Bool = false,
        seed: String? = nil
    ) throws {
        let directory = screenshotsDirectory(locale: locale, deviceClassID: deviceClassID)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try PNGWriter.write(
            to: directory.appending(path: fileName),
            width: width,
            height: height,
            hasAlpha: hasAlpha,
            // Two screenshots in a real set are never the same image. One
            // language's screenshots are never another language's either.
            // Making the colour follow the folder and the name keeps the
            // fixtures honest, so a test about ordering is really about
            // ordering.
            //
            // Pass a seed to write one picture into two languages. That is what
            // a language nobody translated the screenshots for looks like.
            seed: seed ?? "\(locale)/\(deviceClassID)/\(fileName)"
        )
    }

    func writeNonImage(locale: String, deviceClassID: String, named fileName: String) throws {
        let directory = screenshotsDirectory(locale: locale, deviceClassID: deviceClassID)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not an image".utf8).write(to: directory.appending(path: fileName))
    }

    /// Sets when every screenshot in one set was last written.
    ///
    /// A test that writes two folders in a row gets two dates a millisecond
    /// apart, and which one is newer then depends on how fast the machine is.
    /// Saying the date makes the test about the rule rather than about that.
    func setModified(locale: String, deviceClassID: String, to date: Date) throws {
        let directory = screenshotsDirectory(locale: locale, deviceClassID: deviceClassID)
        for url in try FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) {
            try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path)
        }
    }

    func screenshotsDirectory(locale: String, deviceClassID: String) -> URL {
        rootURL
            .appending(path: "versions").appending(path: version)
            .appending(path: "screenshots").appending(path: locale).appending(path: deviceClassID)
    }

    // MARK: - Reading back

    func load() throws -> Project {
        try Project.load(at: rootURL)
    }

    func content() throws -> VersionContent {
        try ContentStore.load(version: version, in: load())
    }

    func problems() throws -> [Problem] {
        try check().problems
    }

    func check(version requested: String? = nil) throws -> CheckResult {
        try Checker.check(project: load(), version: requested)
    }
}

/// Writes a real PNG, so the alpha channel and the pixel size the validator
/// reads are the ones a design tool would actually produce.
enum PNGWriter {
    static func write(
        to url: URL,
        width: Int,
        height: Int,
        hasAlpha: Bool,
        seed: String = ""
    ) throws {
        let alphaInfo: CGImageAlphaInfo = hasAlpha ? .premultipliedLast : .noneSkipLast
        guard
            let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: alphaInfo.rawValue
            )
        else {
            throw FixtureError.couldNotMakeContext
        }

        context.setFillColor(colour(for: seed))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        guard
            let image = context.makeImage(),
            let destination = CGImageDestinationCreateWithURL(
                url as CFURL,
                UTType.png.identifier as CFString,
                1,
                nil
            )
        else {
            throw FixtureError.couldNotWritePNG
        }

        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw FixtureError.couldNotWritePNG }
    }

    /// The colour this seed paints, worked out the same way in every run.
    ///
    /// `hashValue` is seeded afresh in each process, so two seeds that paint
    /// the same colour in one run paint different colours in the next. Two
    /// screenshots that collide are one file byte for byte, which makes the
    /// copies-of-source rule warn about a picture somebody did translate. A
    /// test that reads the first screenshot warning then fails about once in
    /// two hundred runs.
    ///
    /// Three channels off one stable hash, so a collision needs 24 bits to
    /// agree rather than eight.
    private static func colour(for seed: String) -> CGColor {
        var hash = 5381
        for byte in seed.utf8 {
            hash = (hash &* 33 &+ Int(byte)) & 0xFFFFFF
        }
        return CGColor(
            red: Double((hash >> 16) & 0xFF) / 255,
            green: Double((hash >> 8) & 0xFF) / 255,
            blue: Double(hash & 0xFF) / 255,
            alpha: 1
        )
    }

    enum FixtureError: Error {
        case couldNotMakeContext
        case couldNotWritePNG
    }
}
