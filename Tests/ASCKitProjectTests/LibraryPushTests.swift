import ASCKitAPI
import ASCKitTestSupport
import Foundation
import Synchronization
import Testing
@testable import ASCKitProject

/// Replies for the library, shaped like Apple's examples.
enum LibraryReply {
    static func reserved(_ id: String) -> StubTransport.Reply {
        .ok("""
        {"data":{"type":"appAssetLibraryImages","id":"\(id)","attributes":{"state":"AWAITING_UPLOAD",
          "uploadOperations":[{"method":"PUT","url":"https://blob.example.test/\(id)",
            "length":1,"offset":0,"requestHeaders":[]}]}}}
        """)
    }

    static let committed = StubTransport.Reply.ok(
        #"{"data":{"type":"appAssetLibraryImages","id":"x","attributes":{"state":"UPLOAD_COMPLETE"}}}"#
    )

    static func states(_ pairs: [(String, String)]) -> StubTransport.Reply {
        let list = pairs.map { id, state in
            #"{"type":"appAssetLibraryImages","id":"\#(id)","attributes":{"state":"\#(state)","#
                + #""stateDetails":[{"code":"IMAGE_TOO_SMALL","description":"The image is too small."}]}}"#
        }
        return .ok(#"{"data":[\#(list.joined(separator: ","))]}"#)
    }

    static func placement(_ id: String) -> StubTransport.Reply {
        .ok(#"{"data":{"type":"appAssetLibraryPlacements","id":"\#(id)","attributes":{}}}"#)
    }

    static let ordered = StubTransport.Reply.ok(
        #"{"data":{"type":"appAssetLibraryPlacementOrderingRequests","id":"o1"}}"#
    )

    static let deleted = StubTransport.Reply(status: 204, body: Data())

    static func refusal(_ code: String) -> StubTransport.Reply {
        .failure(409, #"{"errors":[{"status":"409","code":"\#(code)","detail":"Refused."}]}"#)
    }
}

/// What a test sees of the record the pusher saves.
actor SavedRecords {
    private(set) var saved: [AssetRecord] = []
    func add(_ record: AssetRecord) {
        saved.append(record)
    }
}

struct LibraryPusherTests {
    let files: LibraryFiles

    init() throws {
        files = try LibraryFiles()
    }

    func target(
        _ id: String = "en-US|iphone-6.9",
        locale: String = "loc-en",
        local: [ScreenshotFile],
        current: [RemotePlacement] = [],
        record: AssetRecord = AssetRecord()
    ) -> LibraryPusher.Target {
        LibraryPusher.Target(
            id: id,
            label: id,
            deviceClassID: DeviceClass.iPhone69.id,
            parent: .versionLocalization(id: locale),
            files: local.map(\.libraryFile),
            slot: LibraryPlanner.slot(files: local.map(\.libraryFile), current: current, record: record,
                                      group: Placed.group, type: .appScreenshot)
        )
    }

    func push(
        _ targets: [LibraryPusher.Target],
        transport: StubTransport,
        record: AssetRecord = AssetRecord(),
        saved: SavedRecords = SavedRecords()
    ) async throws -> (result: ScreenshotPusher.Result, record: AssetRecord) {
        let pusher = try LibraryPusher(client: ASCClient.stubbed(transport: transport), poll: .immediate, uploadLimit: 1)
        return await pusher.push(targets, libraryID: "lib1", record: record, saveRecord: { record in
            Task { await saved.add(record) }
        })
    }

    static func calls(_ transport: StubTransport) async -> [String] {
        await transport.requests.map { "\($0.httpMethod ?? "") \($0.url?.path ?? "")" }
    }

    // MARK: - The order of the work

    @Test func uploadsWaitsRemovesPlacesInThatOrder() async throws {
        defer { files.remove() }
        let one = try files.file("01.png")
        let transport = StubTransport([
            LibraryReply.reserved("new1"), .ok(""), LibraryReply.committed,
            LibraryReply.states([("new1", "PREPARE_FOR_SUBMISSION")]),
            LibraryReply.deleted,
            LibraryReply.placement("p-new")
        ])

        let pushed = try await push([target(local: [one], current: [Placed.placement("p-old", asset: "unknown")])],
                                    transport: transport)

        #expect(pushed.result.isCompleteSuccess)
        #expect(await Self.calls(transport) == [
            "POST /v1/appAssetLibraryImages",
            "PUT /new1",
            "PATCH /v1/appAssetLibraryImages/new1",
            "GET /v1/appAssetLibraries/lib1/images",
            "DELETE /v1/appAssetLibraryPlacements/p-old",
            "POST /v1/appAssetLibraryPlacements",
            "GET /v1/appAssetLibraries/lib1/images"
        ], "the last read asks whether anything still places the old asset")
        #expect(try pushed.record.assetID(md5: LibraryFiles.md5(one), fileSize: one.byteCount) == "new1")
        #expect(pushed.record.assets.values.first?.state == .prepareForSubmission)
    }

    @Test func savesTheRecordAsSoonAsAnUploadCommits() async throws {
        defer { files.remove() }
        let one = try files.file("01.png")
        let saved = SavedRecords()
        let transport = StubTransport([
            LibraryReply.reserved("new1"), .ok(""), LibraryReply.committed,
            LibraryReply.states([("new1", "PREPARE_FOR_SUBMISSION")]),
            LibraryReply.placement("p-new")
        ])

        _ = try await push([target(local: [one])], transport: transport, saved: saved)
        try await Task.sleep(for: .milliseconds(50))

        let first = try #require(await saved.saved.first)
        #expect(try first.assetID(md5: LibraryFiles.md5(one), fileSize: one.byteCount) == "new1")
    }

    @Test func onlySetsTheOrderWhenOnlyTheOrderChanged() async throws {
        defer { files.remove() }
        let one = try files.file("01.png"), two = try files.file("02.png")
        let record = try LibraryFiles.record([(one, "a1"), (two, "a2")])
        let transport = StubTransport([LibraryReply.ordered])

        let pushed = try await push(
            [target(local: [one, two], current: [Placed.placement("p2", asset: "a2"), Placed.placement("p1", asset: "a1")],
                    record: record)],
            transport: transport,
            record: record
        )

        #expect(pushed.result.isCompleteSuccess)
        #expect(await Self.calls(transport) == ["POST /v1/appAssetLibraryPlacementOrderingRequests"])
        let body = try #require(await transport.request(at: 0).httpBody)
        let text = try #require(String(bytes: body, encoding: .utf8))
        #expect(try #require(text.range(of: "p1")).lowerBound < #require(text.range(of: "p2")).lowerBound)
    }

    @Test func placesAnAssetTheLibraryAlreadyHoldsWithNoUpload() async throws {
        defer { files.remove() }
        let one = try files.file("01.png")
        let record = try LibraryFiles.record([(one, "a1")])
        let transport = StubTransport([LibraryReply.placement("p-new")])

        let pushed = try await push([target(local: [one], record: record)], transport: transport, record: record)

        #expect(pushed.result.isCompleteSuccess)
        #expect(await Self.calls(transport) == ["POST /v1/appAssetLibraryPlacements"])
    }

    /// The bug this guards against: a push that made a placement and said
    /// nothing about it, between the plan and "setting the order".
    @Test func saysItPlacesAnAssetTheLibraryAlreadyHolds() async throws {
        defer { files.remove() }
        let one = try files.file("01.png")
        let record = try LibraryFiles.record([(one, "a1")])
        let transport = StubTransport([LibraryReply.placement("p-new")])
        let steps = Mutex<[String]>([])

        let pusher = try LibraryPusher(client: ASCClient.stubbed(transport: transport), poll: .immediate, uploadLimit: 1)
        _ = await pusher.push([target(local: [one], record: record)], libraryID: "lib1", record: record,
                              saveRecord: { _ in }, progress: { step in steps.withLock { $0.append(step.label) } })

        #expect(steps.withLock { $0 } == ["en-US|iphone-6.9 iphone-6.9: placing 1 image"])
    }

    @Test func uploadsOneFileOnceForEveryLanguageThatUsesIt() async throws {
        defer { files.remove() }
        let one = try files.file("01.png")
        let transport = StubTransport(routes: [
            ("/v1/appAssetLibraryImages/new1", LibraryReply.committed),
            ("/v1/appAssetLibraryImages", LibraryReply.reserved("new1")),
            ("/new1", .ok("")),
            ("/appAssetLibraries/lib1/images", LibraryReply.states([("new1", "PREPARE_FOR_SUBMISSION")])),
            ("/appAssetLibraryPlacements", LibraryReply.placement("p"))
        ])

        let pushed = try await push(
            [target("en", locale: "loc-en", local: [one]), target("de", locale: "loc-de", local: [one]),
             target("fr", locale: "loc-fr", local: [one])],
            transport: transport
        )

        #expect(pushed.result.uploaded.sorted() == ["de", "en", "fr"])
        let calls = await Self.calls(transport)
        #expect(calls.filter { $0 == "POST /v1/appAssetLibraryImages" }.count == 1)
        #expect(calls.filter { $0 == "POST /v1/appAssetLibraryPlacements" }.count == 3)
    }

    @Test func namesEachUploadByLanguage() async throws {
        defer { files.remove() }
        let english = try files.file("01.png", contents: "en")
        let german = try files.file("02.png", contents: "de")
        let transport = StubTransport(routes: [
            ("/v1/appAssetLibraryImages/new1", LibraryReply.committed),
            ("/v1/appAssetLibraryImages", LibraryReply.reserved("new1")),
            ("/new1", .ok("")),
            ("/appAssetLibraries/lib1/images", LibraryReply.states([("new1", "PREPARE_FOR_SUBMISSION")])),
            ("/appAssetLibraryPlacements", LibraryReply.placement("p"))
        ])

        _ = try await push([target("en-US", local: [english]), target("de-DE", local: [german])],
                           transport: transport)

        let bodies = await transport.requests
            .filter { $0.httpMethod == "POST" && $0.url?.path == "/v1/appAssetLibraryImages" }
            .compactMap { $0.httpBody.flatMap { String(data: $0, encoding: .utf8) } }
        #expect(bodies.count == 2)
        for name in ["en-US 01.png", "de-DE 02.png"] {
            #expect(bodies.contains { $0.contains(#""referenceName":"\#(name)""#) })
        }
    }

    @Test func renamesTheAssetAChangedFileReplaces() async throws {
        defer { files.remove() }
        let one = try files.file("01.png", contents: "new")
        let old = RemotePlacement(
            id: "p-old", locale: "en-US", type: .appScreenshot, group: Placed.group, state: .parentPrepareForSubmission,
            asset: RemoteLibraryAsset(id: "old12345abc", media: .image, fileName: "01.png",
                                      referenceName: "en-US|iphone-6.9 01.png", state: .prepareForSubmission)
        )
        let transport = StubTransport([
            .ok(#"{"data":{"type":"appAssetLibraryImages","id":"old12345abc","attributes":{}}}"#),
            LibraryReply.reserved("new1"), .ok(""), LibraryReply.committed,
            LibraryReply.states([("new1", "PREPARE_FOR_SUBMISSION")]),
            LibraryReply.deleted,
            LibraryReply.placement("p-new")
        ])

        let pushed = try await push([target(local: [one], current: [old])], transport: transport)

        #expect(pushed.result.isCompleteSuccess)
        #expect(await Array(Self.calls(transport).prefix(2)) == [
            "PATCH /v1/appAssetLibraryImages/old12345abc",
            "POST /v1/appAssetLibraryImages"
        ])
        let rename = try #require(await transport.request(at: 0).httpBody.flatMap { String(data: $0, encoding: .utf8) })
        #expect(rename.contains(#""referenceName":"en-US|iphone-6.9 01.png (replaced old12345)""#))
        let reserve = try #require(await transport.request(at: 1).httpBody.flatMap { String(data: $0, encoding: .utf8) })
        #expect(reserve.contains(#""referenceName":"en-US|iphone-6.9 01.png""#))
        #expect(pushed.result.archived.isEmpty, "an asset in Prepare for Submission cannot be archived")
    }

    static func listed(_ id: String, state: String, placements: [String]) -> StubTransport.Reply {
        let data = placements.map { #"{"type":"appAssetLibraryPlacements","id":"\#($0)"}"# }.joined(separator: ",")
        return .ok(#"{"data":[{"type":"appAssetLibraryImages","id":"\#(id)","attributes":{"state":"\#(state)"},"#
            + #""relationships":{"placements":{"data":[\#(data)]}}}]}"#)
    }

    @Test func archivesAnApprovedAssetNothingPlaces() async throws {
        defer { files.remove() }
        let one = try files.file("01.png")
        let record = try LibraryFiles.record([(one, "a1")])
        let transport = StubTransport([
            LibraryReply.deleted,
            LibraryReply.placement("p-new"),
            Self.listed("old", state: "APPROVED", placements: []),
            .ok(#"{"data":{"type":"appAssetLibraryImages","id":"old","attributes":{}}}"#)
        ])

        let pushed = try await push([target(local: [one], current: [Placed.placement("p-old", asset: "old")],
                                            record: record)],
                                    transport: transport, record: record)

        #expect(pushed.result.archived.map(\.id) == ["old"])
        #expect(await Self.calls(transport).suffix(2) == [
            "GET /v1/appAssetLibraries/lib1/images",
            "PATCH /v1/appAssetLibraryImages/old"
        ])
        let body = try #require(await transport.request(at: 3).httpBody.flatMap { String(data: $0, encoding: .utf8) })
        #expect(body.contains(#""archived":true"#))
    }

    @Test func keepsAnAssetAnotherVersionPlaces() async throws {
        defer { files.remove() }
        let one = try files.file("01.png")
        let record = try LibraryFiles.record([(one, "a1")])
        let transport = StubTransport([
            LibraryReply.deleted,
            LibraryReply.placement("p-new"),
            Self.listed("old", state: "APPROVED", placements: ["p-live"])
        ])

        let pushed = try await push([target(local: [one], current: [Placed.placement("p-old", asset: "old")],
                                            record: record)],
                                    transport: transport, record: record)

        #expect(pushed.result.archived.isEmpty)
        #expect(await Self.calls(transport).last == "GET /v1/appAssetLibraries/lib1/images")
    }

    // MARK: - Failing partway

    @Test func placesNothingInASlotWhoseUploadFailed() async throws {
        defer { files.remove() }
        let one = try files.file("01.png")
        let transport = StubTransport([LibraryReply.refusal("ENTITY_ERROR")])

        let pushed = try await push([target(local: [one], current: [Placed.placement("p-old", asset: "x")])],
                                    transport: transport)

        #expect(pushed.result.failed.map(\.locale) == ["en-US|iphone-6.9"])
        #expect(pushed.result.failed.first?.message.contains("01.png") == true)
        #expect(await Self.calls(transport) == ["POST /v1/appAssetLibraryImages"], "the old placement stays")
        #expect(pushed.record.isEmpty)
    }

    @Test func keepsWhatCommittedAndSendsOnlyTheRestNextTime() async throws {
        defer { files.remove() }
        let one = try files.file("01.png"), two = try files.file("02.png")
        let transport = StubTransport([
            LibraryReply.reserved("a1"), .ok(""), LibraryReply.committed,
            LibraryReply.refusal("ENTITY_ERROR"),
            LibraryReply.states([("a1", "PREPARE_FOR_SUBMISSION")])
        ])

        let first = try await push([target(local: [one, two])], transport: transport)

        #expect(first.result.isCompleteSuccess == false)
        #expect(try first.record.assetID(md5: LibraryFiles.md5(one), fileSize: one.byteCount) == "a1")

        let again = target(local: [one, two], record: first.record)
        #expect(again.slot.wanted == ["a1", nil])
        #expect(try LibraryPusher.uploads(in: [again]).keys.sorted() == [LibraryFiles.md5(two)])
    }

    @Test func reportsAnImageAppStoreConnectRefusedAfterProcessing() async throws {
        defer { files.remove() }
        let one = try files.file("01.png")
        let transport = StubTransport([
            LibraryReply.reserved("new1"), .ok(""), LibraryReply.committed,
            LibraryReply.states([("new1", "FAILED")])
        ])

        let pushed = try await push([target(local: [one])], transport: transport)

        #expect(pushed.result.failed.first?.message.contains("The image is too small.") == true)
        #expect(pushed.record.assets.values.first?.state == .failed)
        #expect(await Self.calls(transport).contains("POST /v1/appAssetLibraryPlacements") == false)
    }

    @Test func reportsAnImageStillProcessingAfterTheLastCheck() async throws {
        defer { files.remove() }
        let one = try files.file("01.png")
        let transport = StubTransport(routes: [
            ("/v1/appAssetLibraryImages/new1", LibraryReply.committed),
            ("/v1/appAssetLibraryImages", LibraryReply.reserved("new1")),
            ("/new1", .ok("")),
            ("/appAssetLibraries/lib1/images", LibraryReply.states([("new1", "UPLOAD_COMPLETE")]))
        ])

        let pushed = try await push([target(local: [one])], transport: transport)

        #expect(pushed.result.failed.first?.message.contains("still working on 01.png") == true)
    }

    @Test func goesOnWithTheOtherSlotsWhenOneParentRefuses() async throws {
        defer { files.remove() }
        let one = try files.file("01.png")
        let record = try LibraryFiles.record([(one, "a1")])
        let transport = StubTransport(
            bodyRoutes: [("loc-bad", LibraryReply.refusal("STATE_ERROR.INVALID_STATE"))],
            otherwise: LibraryReply.placement("p")
        )

        let pushed = try await push(
            [target("bad", locale: "loc-bad", local: [one], record: record),
             target("good", locale: "loc-good", local: [one], record: record)],
            transport: transport,
            record: record
        )

        #expect(pushed.result.uploaded == ["good"])
        #expect(pushed.result.failed.map(\.locale) == ["bad"])
        #expect(pushed.result.failed.first?.message.contains("does not take changes to bad") == true)
    }

    @Test func namesTheGroupWhenAppStoreConnectRefusesTheCombination() async throws {
        defer { files.remove() }
        let one = try files.file("01.png")
        let record = try LibraryFiles.record([(one, "a1")])
        let transport = StubTransport([LibraryReply.refusal("ENTITY_ERROR.ATTRIBUTE.INVALID")])

        let pushed = try await push([target(local: [one], record: record)], transport: transport, record: record)

        #expect(pushed.result.failed.first?.message.contains(Placed.group) == true)
    }

    @Test func doesNothingForAnEmptyPush() async throws {
        let transport = StubTransport([])
        let pushed = try await push([], transport: transport)
        #expect(pushed.result.isCompleteSuccess)
        #expect(await transport.requestCount == 0)
    }
}

// MARK: - Pruning

struct LibraryPruneTests {
    struct Asset {
        let id: String
        let state: LibraryAssetState
        let placements: Int
    }

    static func library(_ assets: [Asset]) -> RemoteAssetLibrary {
        RemoteAssetLibrary(
            id: "lib1",
            assets: assets.map { RemoteLibraryAsset(id: $0.id, media: .image, fileName: "\($0.id).png", state: $0.state) },
            placementIDs: Dictionary(uniqueKeysWithValues: assets.map { ($0.id, (0 ..< $0.placements).map { "p\($0)" }) })
        )
    }

    @Test func picksOnlyUnplacedAssetsInPrepareForSubmission() {
        let library = Self.library([
            Asset(id: "unplaced-draft", state: .prepareForSubmission, placements: 0),
            Asset(id: "placed-draft", state: .prepareForSubmission, placements: 1),
            Asset(id: "unplaced-approved", state: .approved, placements: 0),
            Asset(id: "unplaced-processing", state: .uploadComplete, placements: 0)
        ])
        #expect(PushSession.pruneCandidates(in: library).map(\.id) == ["unplaced-draft"])
    }

    @Test func deletesTheCandidatesAndForgetsThem() async throws {
        let fixture = try FixtureProject()
        defer { fixture.remove() }
        try fixture.writeConfig(ProjectConfig(bundleID: "com.example.Demo", keyID: "K", issuerID: "I", locales: ["en-US"]))
        let project = try fixture.load()
        var record = AssetRecord()
        record.record(md5: "gone", AssetRecord.Entry(assetID: "a", media: .image, fileName: "a.png", fileSize: 1))
        record.record(md5: "kept", AssetRecord.Entry(assetID: "b", media: .image, fileName: "b.png", fileSize: 1))
        try AssetRecordStore.save(record, in: project)

        let transport = StubTransport([LibraryReply.deleted])
        let session = try PushSession(project: project, client: ASCClient.stubbed(transport: transport))

        let result = await session.prune([RemoteLibraryAsset(id: "a", media: .image)])

        #expect(result.deleted.map(\.id) == ["a"])
        #expect(await transport.request(at: 0).url?.path == "/v1/appAssetLibraryImages/a")
        #expect(try Array(AssetRecordStore.load(in: project).assets.keys) == ["kept"])
    }

    @Test func goesOnWhenAPlacementAppearedInTheMeantime() async throws {
        let fixture = try FixtureProject()
        defer { fixture.remove() }
        try fixture.writeConfig(ProjectConfig(bundleID: "com.example.Demo", keyID: "K", issuerID: "I", locales: ["en-US"]))
        let transport = StubTransport([LibraryReply.refusal("STATE_ERROR.ASSET_HAS_PLACEMENTS"), LibraryReply.deleted])
        let session = try PushSession(project: fixture.load(), client: ASCClient.stubbed(transport: transport))

        let result = await session.prune([
            RemoteLibraryAsset(id: "a", media: .image), RemoteLibraryAsset(id: "b", media: .video)
        ])

        #expect(result.refused.map(\.asset.id) == ["a"])
        #expect(result.deleted.map(\.id) == ["b"])
        #expect(await transport.request(at: 1).url?.path == "/v1/appAssetLibraryVideos/b")
    }
}

extension LibraryPusherTests {
    @Test func datesEachUploadItRecords() async throws {
        defer { files.remove() }
        let one = try files.file("01.png")
        let transport = StubTransport([
            LibraryReply.reserved("new1"), .ok(""), LibraryReply.committed,
            LibraryReply.states([("new1", "PREPARE_FOR_SUBMISSION")]),
            LibraryReply.placement("p")
        ])
        let pusher = try LibraryPusher(client: ASCClient.stubbed(transport: transport), poll: .immediate)
        let date = Date(timeIntervalSince1970: 1_790_000_000)

        let pushed = await pusher.push([target(local: [one])], libraryID: "lib1", record: AssetRecord(),
                                       saveRecord: { _ in }, at: date)

        #expect(pushed.record.assets.values.first?.uploadedAt == date)
    }
}
