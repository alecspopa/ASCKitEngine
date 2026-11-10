import ASCKitTestSupport
import Foundation
import Testing
@testable import ASCKitAPI

struct RetentionMessageTests {
    // MARK: - Reading

    func readingTransport(placement: String = #"{"data":null}"#) -> StubTransport {
        StubTransport(routes: [
            ("/relationships/placement", .ok(placement)),
            ("/localizations", .ok("""
            {"data":[{"type":"retentionMessageLocalizations","id":"w1",
              "attributes":{"locale":"de-DE","header":"Kopf","body":"Text"}}]}
            """)),
            ("/versions", .ok("""
            {"data":[
              {"type":"retentionMessageVersions","id":"v-old","attributes":{"state":"APPROVED"}},
              {"type":"retentionMessageVersions","id":"v-new","attributes":{"state":"PREPARE_FOR_SUBMISSION"}}
            ]}
            """)),
            ("/retentionMessages", .ok("""
            {"data":[{"type":"retentionMessages","id":"m1","attributes":{"referenceName":"Cancel"}}]}
            """))
        ])
    }

    @Test func readsTheDraftWithItsWords() async throws {
        let client = try ASCClient.stubbed(transport: readingTransport())
        let messages = try await client.retentionMessages(appID: "app")

        let message = try #require(messages.first)
        #expect(message.referenceName == "Cancel")
        let version = try #require(message.version)
        #expect(version.id == "v-new")
        #expect(version.acceptsChanges)
        #expect(version.words["de-DE"] == RemoteRetentionWords(id: "w1", header: "Kopf", body: "Text"))
        #expect(version.placementID == nil)
    }

    @Test func readsThePlacementOfTheImage() async throws {
        let transport = readingTransport(placement: #"{"data":{"type":"appAssetLibraryPlacements","id":"p1"}}"#)
        let client = try ASCClient.stubbed(transport: transport)
        let messages = try await client.retentionMessages(appID: "app")
        #expect(messages.first?.version?.placementID == "p1")
    }

    @Test(arguments: [
        (["APPROVED", "IN_REVIEW"], "IN_REVIEW"),
        (["APPROVED", "PREPARE_FOR_SUBMISSION", "REJECTED"], "PREPARE_FOR_SUBMISSION"),
        (["APPROVED"], "APPROVED")
    ])
    func picksTheNewestVersionByState(states: [String], expected: String) throws {
        let versions = states.map {
            Resource(
                type: "retentionMessageVersions", id: $0,
                attributes: RetentionVersionAttributes(state: RetentionVersionState(rawValue: $0)),
                relationships: nil
            )
        }
        #expect(ASCClient.retentionVersion(in: versions)?.id == expected)
    }

    @Test func onlyADraftTakesChanges() {
        #expect(RetentionVersionState.prepareForSubmission.isEditable)
        #expect(RetentionVersionState.approved.isEditable == false)
        #expect(RetentionVersionState.waitingForReview.isEditable == false)
    }

    // MARK: - Writing

    @Test func createsWordsOnTheVersion() async throws {
        let transport = StubTransport(.ok(#"{"data":{"type":"retentionMessageLocalizations","id":"w2"}}"#))
        let client = try ASCClient.stubbed(transport: transport)
        try await client.createRetentionWords(
            versionID: "v1", RetentionWordsWrite(locale: "en-US", header: "Stay", body: "More soon")
        )

        let request = await transport.request(at: 0)
        #expect(request.url?.path == "/v1/retentionMessageLocalizations")
        #expect(request.httpMethod == "POST")
        let data = try #require(request.jsonObject()?["data"] as? [String: Any])
        let attributes = try #require(data["attributes"] as? [String: Any])
        #expect(attributes["locale"] as? String == "en-US")
        #expect(attributes["header"] as? String == "Stay")
        let relationships = try #require(data["relationships"] as? [String: Any])
        let version = try #require(relationships["retentionMessageVersion"] as? [String: Any])
        #expect((version["data"] as? [String: Any])?["id"] as? String == "v1")
    }

    @Test func changesOnlyTheFieldsGiven() async throws {
        let transport = StubTransport(.ok(#"{"data":{"type":"retentionMessageLocalizations","id":"w1"}}"#))
        let client = try ASCClient.stubbed(transport: transport)
        try await client.updateRetentionWords(id: "w1", RetentionWordsWrite(body: "New"))

        let request = await transport.request(at: 0)
        #expect(request.url?.path == "/v1/retentionMessageLocalizations/w1")
        #expect(request.httpMethod == "PATCH")
        let data = try #require(request.jsonObject()?["data"] as? [String: Any])
        let attributes = try #require(data["attributes"] as? [String: Any])
        #expect(attributes.keys.sorted() == ["body"])
    }

    @Test func placesAnImageOnTheVersion() async throws {
        let transport = StubTransport(.ok(#"{"data":{"type":"appAssetLibraryPlacements","id":"p1"}}"#))
        let client = try ASCClient.stubbed(transport: transport)
        _ = try await client.createPlacement(
            type: .retentionMessage, group: "DEFAULT_PROFILE", media: .image, assetID: "a1",
            on: .retentionMessageVersion(id: "v1")
        )

        let request = await transport.request(at: 0)
        let data = try #require(request.jsonObject()?["data"] as? [String: Any])
        let relationships = try #require(data["relationships"] as? [String: Any])
        let version = try #require(relationships["retentionMessageVersion"] as? [String: Any])
        let identifier = try #require(version["data"] as? [String: Any])
        #expect(identifier["type"] as? String == "retentionMessageVersions")
        #expect((data["attributes"] as? [String: Any])?["placementType"] as? String == "RETENTION_MESSAGE_ASSET")
    }
}
