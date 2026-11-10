import ASCKitAPI
import ASCKitTestSupport
import Foundation
import Testing
@testable import ASCKitProject

final class RetentionImagePushTests {
    let fixture: FixtureProject

    init() throws {
        fixture = try FixtureProject()
        _ = try fixture.writeConfig(ProjectConfig(bundleID: "com.example.MyApp", keyID: "ABC123", locales: ["en-US"]))
    }

    deinit {
        fixture.remove()
    }

    func plan(uploaded: String?) -> ChangePlan {
        ChangePlan(
            versionString: "1.0", versionState: nil, textChanges: [], missingLocales: [], screenshotPlans: [],
            retentionImages: [.init(
                message: "Cancel", fileURL: URL(fileURLWithPath: "/tmp/Cancel.png"),
                md5: "abc", fileSize: 3, uploadedAssetID: uploaded
            )],
            blocked: [], skipped: []
        )
    }

    let remote = RemoteProducts(appID: "app", products: [], groupNames: [:], retentionMessages: [
        RemoteRetentionMessage(id: "m1", referenceName: "Cancel", version: RemoteRetentionVersion(
            id: "v1", state: .prepareForSubmission, words: [:], placementID: "p-old", placedAssetID: "a-old"
        ))
    ])

    func push(_ routes: [(String, StubTransport.Reply)]) async throws -> (ProductPusher.TextResult, [URLRequest]) {
        let transport = StubTransport(routes: routes + [
            ("/assetLibrary", .ok(#"{"data":{"type":"appAssetLibraries","id":"lib0"}}"#)),
            ("/appAssetLibraryRefData", .ok(#"{"data":[]}"#))
        ])
        let session = try PushSession(project: fixture.load(), client: ASCClient.stubbed(transport: transport))
        var result = ProductPusher.TextResult()
        await session.pushRetentionImages(plan(uploaded: "a1"), to: remote, dryRun: false,
                                          progress: nil, into: &result)
        var requests: [URLRequest] = []
        for index in 0 ..< (await transport.requestCount) {
            await requests.append(transport.request(at: index))
        }
        return (result, requests)
    }

    @Test func replacesThePlacementOfTheVersion() async throws {
        let (result, requests) = try await push([
            ("/appAssetLibraryPlacements/p-old", .ok("")),
            ("/appAssetLibraryPlacements", .ok(#"{"data":{"type":"appAssetLibraryPlacements","id":"p-new"}}"#))
        ])
        #expect(result.failed.isEmpty)
        #expect(result.written == ["Cancel Cancel.png"])

        let delete = try #require(requests.first { $0.httpMethod == "DELETE" })
        #expect(delete.url?.path == "/v1/appAssetLibraryPlacements/p-old")
        let create = try #require(requests.first { $0.httpMethod == "POST" })
        let data = try #require(create.jsonObject()?["data"] as? [String: Any])
        let relationships = try #require(data["relationships"] as? [String: Any])
        #expect(((relationships["image"] as? [String: Any])?["data"] as? [String: Any])?["id"] as? String == "a1")
        #expect(relationships["retentionMessageVersion"] != nil)
    }

    @Test func saysSoWhenThePlacementIsRefused() async throws {
        let (result, _) = try await push([
            ("/appAssetLibraryPlacements/p-old", .ok("")),
            ("/appAssetLibraryPlacements", .failure(409))
        ])
        #expect(result.written.isEmpty)
        #expect(result.failed.map(\.productID) == ["Cancel"])
    }

    @Test func aDryRunSendsNothing() async throws {
        let transport = StubTransport(routes: [])
        let session = try PushSession(project: fixture.load(), client: ASCClient.stubbed(transport: transport))
        var result = ProductPusher.TextResult()
        await session.pushRetentionImages(plan(uploaded: nil), to: remote, dryRun: true, progress: nil, into: &result)
        #expect(result.wouldSend.count == 1)
        #expect(await transport.requestCount == 0)
    }
}
