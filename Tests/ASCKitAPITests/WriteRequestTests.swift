import ASCKitTestSupport
import Foundation
import Testing
@testable import ASCKitAPI

/// The write calls, checked at the level of the JSON that leaves the machine.
struct WriteRequestTests {
    func body(of request: URLRequest) throws -> [String: Any] {
        let json = try #require(request.jsonObject())
        return try #require(json["data"] as? [String: Any])
    }

    func attributes(of request: URLRequest) throws -> [String: Any] {
        try #require(try body(of: request)["attributes"] as? [String: Any])
    }

    static let versionLocalization = """
    {"data":{"type":"appStoreVersionLocalizations","id":"v1","attributes":{"locale":"en-US"}}}
    """
    static let appInfoLocalization = """
    {"data":{"type":"appInfoLocalizations","id":"i1","attributes":{"locale":"en-US"}}}
    """

    // MARK: - Only what changed

    /// A field left nil is left out of the body entirely, so App Store Connect
    /// leaves it alone rather than being told to blank it.
    @Test func leavesOutAFieldThatWasNotGiven() async throws {
        let transport = StubTransport(.ok(Self.versionLocalization))
        let client = try ASCClient.stubbed(transport: transport)

        _ = try await client.updateVersionLocalization(id: "v1", keywords: "household,restock")

        let sent = try await attributes(of: transport.request(at: 0))
        #expect(sent["keywords"] as? String == "household,restock")
        #expect(sent["description"] == nil)
        #expect(sent["whatsNew"] == nil)
        #expect(sent["supportUrl"] == nil)
    }

    /// An empty string is a real value that blanks the field, so it must reach
    /// App Store Connect when it is deliberately given.
    @Test func sendsAnEmptyStringWhenOneIsGiven() async throws {
        let transport = StubTransport(.ok(Self.versionLocalization))
        let client = try ASCClient.stubbed(transport: transport)

        _ = try await client.updateVersionLocalization(id: "v1", promotionalText: "")

        #expect(try await attributes(of: transport.request(at: 0))["promotionalText"] as? String == "")
    }

    // MARK: - The right resource

    @Test func writesTheSupportAddressToTheVersion() async throws {
        let transport = StubTransport(.ok(Self.versionLocalization))
        let client = try ASCClient.stubbed(transport: transport)

        _ = try await client.updateVersionLocalization(id: "v1", supportUrl: "https://example.com")

        let request = await transport.request(at: 0)
        #expect(request.httpMethod == "PATCH")
        #expect(request.url?.path == "/v1/appStoreVersionLocalizations/v1")
        #expect(try body(of: request)["type"] as? String == "appStoreVersionLocalizations")
    }

    @Test func writesThePrivacyPolicyToTheAppInformation() async throws {
        let transport = StubTransport(.ok(Self.appInfoLocalization))
        let client = try ASCClient.stubbed(transport: transport)

        _ = try await client.updateAppInfoLocalization(
            id: "i1",
            privacyPolicyUrl: "https://example.com/privacy"
        )

        let request = await transport.request(at: 0)
        #expect(request.url?.path == "/v1/appInfoLocalizations/i1")
        #expect(try attributes(of: request)["privacyPolicyUrl"] as? String
            == "https://example.com/privacy")
    }

    // MARK: - The path comes from the type

    @Test func sendsACreateToThePathOfItsType() async throws {
        let transport = StubTransport(.ok(Self.versionLocalization))
        let client = try ASCClient.stubbed(transport: transport)

        _ = try await client.create(
            WriteRequest.create(
                "appStoreVersionLocalizations",
                attributes: VersionLocalizationWrite(description: "Wissen, was da ist."),
                relationships: ["appStoreVersion": RelationshipToOne(type: "appStoreVersions", id: "ver1")]
            ),
            as: VersionLocalizationAttributes.self
        )

        let request = await transport.request(at: 0)
        #expect(request.httpMethod == "POST")
        #expect(request.url?.path == "/v1/appStoreVersionLocalizations")
        #expect(try body(of: request)["id"] == nil)

        let relationships = try #require(try body(of: request)["relationships"] as? [String: Any])
        let parent = try #require(relationships["appStoreVersion"] as? [String: Any])
        #expect((parent["data"] as? [String: Any])?["id"] as? String == "ver1")
    }

    @Test func sendsAWordsWriteToTheSecondVersionOfTheAPI() async throws {
        let transport = StubTransport(.ok(#"{"data":{"type":"inAppPurchaseLocalizations","id":"l1"}}"#))
        let client = try ASCClient.stubbed(transport: transport)

        try await client.updateWords(of: .inAppPurchase, id: "l1", WordsWrite(name: "Coins"))

        let request = await transport.request(at: 0)
        #expect(request.httpMethod == "PATCH")
        #expect(request.url?.path == "/v2/inAppPurchaseLocalizations/l1")
        #expect(try attributes(of: request)["name"] as? String == "Coins")
        #expect(try attributes(of: request)["description"] == nil)
    }

    /// An update carries the id in the body as well as the path, which is what
    /// JSON:API asks for.
    @Test func carriesTheIdentifierInTheBodyOnAnUpdate() async throws {
        let transport = StubTransport(.ok(Self.versionLocalization))
        let client = try ASCClient.stubbed(transport: transport)

        _ = try await client.updateVersionLocalization(id: "v1", keywords: "one,two")

        #expect(try await body(of: transport.request(at: 0))["id"] as? String == "v1")
    }
}
