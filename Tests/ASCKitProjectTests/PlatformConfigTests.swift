import ASCKitAPI
import ASCKitTestSupport
import Foundation
import Testing
@testable import ASCKitProject

/// Which platform's version a project writes.
///
/// An app on one platform names none, and App Store Connect answers with the
/// version the app has. An app sold as a universal purchase has a version per
/// platform, and the words in one project folder belong to one of them.
final class PlatformConfigTests {
    let fixture: FixtureProject

    init() throws {
        fixture = try FixtureProject()
    }

    deinit {
        fixture.remove()
    }

    func config(platform: String?) -> ProjectConfig {
        ProjectConfig(
            bundleID: "com.example.Demo",
            keyID: "ABC123",
            locales: ["en-US"],
            platform: platform
        )
    }

    // MARK: - Reading the name

    @Test func readsTheNameAConfigurationFileWrites() {
        #expect(config(platform: "ios").resolvedPlatform == .ios)
        #expect(config(platform: "macos").resolvedPlatform == .macOS)
        #expect(config(platform: "tvos").resolvedPlatform == .tvOS)
        #expect(config(platform: "visionos").resolvedPlatform == .visionOS)
    }

    /// A person writing macOS the way Apple writes it means the same platform.
    @Test func readsTheNameWhateverCaseItIsWrittenIn() {
        #expect(config(platform: "macOS").resolvedPlatform == .macOS)
    }

    @Test func namesNoPlatformWhenTheProjectNamesNone() {
        #expect(config(platform: nil).resolvedPlatform == nil)
        #expect(hasPlatformProblem(config(platform: nil)) == false)
    }

    /// A name ASCKit cannot place reads as nil, the same as no name at all, so
    /// the validator is what tells a person which of the two they have.
    @Test func reportsANameItCannotPlace() {
        #expect(config(platform: "mac").resolvedPlatform == nil)
        #expect(hasPlatformProblem(config(platform: "mac")))
    }

    private func hasPlatformProblem(_ config: ProjectConfig) -> Bool {
        Validator(config: config).validateConfiguration().contains { $0.kind == .platformNotKnown }
    }

    // MARK: - The file

    /// A project written before this key existed has no platform line, and
    /// reads as an app on one platform.
    @Test func readsAConfigurationFileWithNoPlatformLine() throws {
        let json = #"{"bundleId":"com.example.Demo","keyId":"ABC123"}"#
        let config = try JSONDecoder().decode(ProjectConfig.self, from: Data(json.utf8))

        #expect(config.platform == nil)
    }

    @Test func keepsThePlatformThroughTheFile() throws {
        try fixture.writeConfig(config(platform: "macos"))

        #expect(try fixture.load().config.platform == "macos")
    }

    // MARK: - Asking App Store Connect

    /// The canned replies are `PushSessionTests`', because this asks what the
    /// push asks: one read of one listing.
    @Test func asksForTheVersionsOfThePlatformTheProjectNames() async throws {
        try fixture.writeConfig(config(platform: "macos"))
        let transport = StubTransport(routes: StubTransport.emptyLibraryRoutes + [
            ("/appScreenshotSets", .ok(#"{"data":[]}"#)),
            ("/appInfoLocalizations", .ok(PushSessionTests.appInfoLocalizationsJSON)),
            ("/appStoreVersionLocalizations", .ok(PushSessionTests.versionLocalizationsJSON)),
            ("/appInfos", .ok(PushSessionTests.appInfosJSON)),
            ("/appStoreVersions", .ok(PushSessionTests.versionsJSON("1.0"))),
            ("/apps", .ok(PushSessionTests.appJSON))
        ])
        let session = try PushSession(
            project: fixture.load(),
            client: ASCClient.stubbed(transport: transport)
        )

        _ = try await session.read(includeScreenshots: false, includeProducts: false)

        let asked = await transport.requests.compactMap(\.url?.absoluteString)
        #expect(asked.contains { $0.contains("appStoreVersions") && $0.contains("MAC_OS") })
    }
}
