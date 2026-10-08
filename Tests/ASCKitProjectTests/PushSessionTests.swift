import ASCKitAPI
import ASCKitTestSupport
import Foundation
import Testing
@testable import ASCKitProject

/// The one way anything writes a listing.
///
/// Both the app and the command line tool push through this, so what is tested
/// here is what both of them do. The record filed afterwards is the part that
/// used to be one front end's job and is now nobody's to forget.
final class PushSessionTests {
    let fixture: FixtureProject

    init() throws {
        fixture = try FixtureProject()
        try fixture.writeConfig(ProjectConfig(
            bundleID: "com.example.Demo",
            keyID: "ABC123",
            issuerID: "issuer",
            sourceLocale: "en-US",
            locales: ["en-US"],
            deviceClasses: [DeviceClass.iPhone69.id]
        ))
        try fixture.writeCopy(AppInformation(
            locale: "en-US",
            status: .approved,
            fields: AppInformation.Fields(
                name: "Demo",
                subtitle: "The new subtitle",
                keywords: "household,restock",
                description: "Know what you have.",
                supportUrl: "https://example.com/support",
                privacyPolicyUrl: "https://example.com/privacy"
            )
        ))
    }

    deinit {
        fixture.remove()
    }

    // MARK: - A recorded App Store Connect

    static let appJSON = """
    {"data":[{"type":"apps","id":"app1",
      "attributes":{"name":"Demo","bundleId":"com.example.Demo"}}]}
    """

    static func versionsJSON(_ versionString: String) -> String {
        """
        {"data":[{"type":"appStoreVersions","id":"v1","attributes":{
          "versionString":"\(versionString)","appVersionState":"PREPARE_FOR_SUBMISSION"}}]}
        """
    }

    static let appInfosJSON = """
    {"data":[{"type":"appInfos","id":"info1","attributes":{"state":"PREPARE_FOR_SUBMISSION"}}]}
    """

    static let versionLocalizationsJSON = """
    {"data":[{"type":"appStoreVersionLocalizations","id":"vloc-en","attributes":{
      "locale":"en-US","description":"Know what you have.","keywords":"household,restock",
      "supportUrl":"https://example.com/support"}}]}
    """

    static let appInfoLocalizationsJSON = """
    {"data":[{"type":"appInfoLocalizations","id":"iloc-en","attributes":{
      "locale":"en-US","name":"Demo","subtitle":"The old subtitle",
      "privacyPolicyUrl":"https://example.com/privacy"}}]}
    """

    static let writtenLocalizationJSON = """
    {"data":{"type":"appInfoLocalizations","id":"iloc-en","attributes":{
      "locale":"en-US","name":"Demo","subtitle":"The new subtitle"}}}
    """

    /// The longer matches come first. A write to one localization and the list
    /// of all of them differ only by what follows the same path.
    func makeSession(versionString: String = "1.0") throws -> PushSession {
        let transport = StubTransport(routes: StubTransport.emptyLibraryRoutes + [
            ("/appInfoLocalizations/iloc-en", .ok(Self.writtenLocalizationJSON)),
            ("/appScreenshotSets", .ok(#"{"data":[]}"#)),
            ("/appInfoLocalizations", .ok(Self.appInfoLocalizationsJSON)),
            ("/appStoreVersionLocalizations", .ok(Self.versionLocalizationsJSON)),
            ("/appInfos", .ok(Self.appInfosJSON)),
            ("/appStoreVersions", .ok(Self.versionsJSON(versionString))),
            ("/apps", .ok(Self.appJSON))
        ])
        return try PushSession(
            project: fixture.load(),
            client: ASCClient.stubbed(transport: transport)
        )
    }

    // MARK: - Reading

    @Test func readsWhatWouldChange() async throws {
        let reading = try await makeSession().read(includeProducts: false)

        #expect(reading.listing.versionString == "1.0")
        #expect(reading.versionToCreate == nil)
        #expect(reading.changes?.textChanges.count == 1)
        #expect(reading.content?.appInformation["en-US"] != nil)
    }

    /// A version App Store Connect moved to and this project has no folder for
    /// is not a broken project. It is reported, and there is nothing to push.
    @Test func readsAVersionWithNoFolderWithoutFailing() async throws {
        let reading = try await makeSession(versionString: "1.1").read(includeProducts: false)

        #expect(reading.versionToCreate == "1.1")
        #expect(reading.changes == nil)
        #expect(reading.content == nil)
    }

    // MARK: - Writing

    @Test func writesTheTextAndTheRecordOfIt() async throws {
        let session = try makeSession()
        let outcome = try await session.pushText(session.read(includeProducts: false))

        #expect(outcome.result.written == ["en-US"])
        #expect(outcome.receiptFailure == nil)

        let url = try #require(outcome.receiptURL)
        #expect(FileManager.default.fileExists(atPath: url.path))
    }

    /// The record is what a person reads weeks later, so a push has to be
    /// findable through the project rather than only through what it returned.
    @Test func leavesTheRecordWhereTheProjectKeepsIt() async throws {
        let session = try makeSession()
        try await session.pushText(session.read(includeProducts: false))

        let history = try PushHistory.read(from: fixture.load())
        #expect(history.count == 1)
        #expect(history.first?.kind == .text)
        #expect(history.first?.version == "1.0")
        #expect(history.first?.written == ["en-US"])
    }

    /// Nothing can be written against a version folder that is not there, and
    /// the refusal has to come before App Store Connect is touched.
    @Test func refusesToPushAgainstAVersionWithNoFolder() async throws {
        let session = try makeSession(versionString: "1.1")
        let reading = try await session.read(includeProducts: false)

        await #expect(throws: ProjectError.self) {
            try await session.pushText(reading)
        }
        await #expect(throws: ProjectError.self) {
            try await session.pushImages(reading)
        }
        #expect(try PushHistory.read(from: fixture.load()).isEmpty)
    }
}
