import ASCKitTestSupport
import Foundation
import Testing
@testable import ASCKitAPI

/// Answers by path, and counts how many requests are open at the same time.
actor CountingTransport: Transport {
    private let reply: @Sendable (URLRequest) -> StubTransport.Reply
    private(set) var open = 0
    private(set) var mostOpen = 0
    private(set) var requests: [URLRequest] = []

    init(reply: @escaping @Sendable (URLRequest) -> StubTransport.Reply) {
        self.reply = reply
    }

    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        open += 1
        mostOpen = max(mostOpen, open)
        // Long enough for every upload the limit allows to be in flight.
        try await Task.sleep(for: .milliseconds(20))
        open -= 1

        let answer = reply(request)
        let response = HTTPURLResponse(
            url: request.url!, statusCode: answer.status, httpVersion: "HTTP/1.1", headerFields: answer.headers
        )!
        let body = answer.status == 204 ? Data() : Data(Self.body(for: request, status: answer.status).utf8)
        return (body, response)
    }

    /// Echoes the reserved id back from the file name, so each upload gets
    /// an id of its own.
    private static func body(for request: URLRequest, status: Int) -> String {
        guard status < 300 else { return #"{"errors":[]}"# }
        let path = request.url?.path ?? ""
        if request.httpMethod == "POST", path == "/v1/appAssetLibraryImages" {
            let sent = String(data: request.httpBody ?? Data(), encoding: .utf8) ?? ""
            let name = sent.range(of: #"file-\d+"#, options: .regularExpression).map { String(sent[$0]) } ?? "x"
            return """
            {"data":{"type":"appAssetLibraryImages","id":"id-\(name)","attributes":{"state":"AWAITING_UPLOAD",
              "uploadOperations":[{"method":"PUT","url":"https://blob.example.test/\(name)",
                "length":10,"offset":0,"requestHeaders":[]}]}}}
            """
        }
        return #"{"data":{"type":"appAssetLibraryImages","id":"x","attributes":{"state":"UPLOAD_COMPLETE"}}}"#
    }
}

struct LibraryUploaderTests {
    let folder: URL

    init() throws {
        folder = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: "asckit-library-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    func removeFolder() {
        try? FileManager.default.removeItem(at: folder)
    }

    func file(_ name: String, bytes: Int = 3000) throws -> URL {
        let url = folder.appending(path: name)
        try Data(repeating: 0xCD, count: bytes).write(to: url)
        return url
    }

    func item(_ name: String, media: LibraryMedia = .image, bytes: Int = 3000) throws -> LibraryUploader.Item {
        try LibraryUploader.Item(fileURL: file(name, bytes: bytes), media: media, category: .screenshotsAndPreviews)
    }

    static func reserved(_ id: String = "img1", operations: String) -> StubTransport.Reply {
        .ok("""
        {"data":{"type":"appAssetLibraryImages","id":"\(id)","attributes":{
          "fileName":"one.png","fileSize":3000,"state":"AWAITING_UPLOAD",
          "uploadOperations":[\(operations)]}}}
        """)
    }

    static let onePart = """
    {"method":"PUT","url":"https://blob.example.test/whole","length":3000,"offset":0,
     "requestHeaders":[{"name":"Content-Type","value":"image/png"}]}
    """

    static let twoParts = """
    {"method":"PUT","url":"https://blob.example.test/a","length":1000,"offset":0,"requestHeaders":[]},
    {"method":"PUT","url":"https://blob.example.test/b","length":2000,"offset":1000,"requestHeaders":[]}
    """

    static let committed = StubTransport.Reply.ok(
        #"{"data":{"type":"appAssetLibraryImages","id":"img1","attributes":{"state":"UPLOAD_COMPLETE"}}}"#
    )

    // MARK: - One file

    @Test func reservesSendsAndCommitsWithNoWait() async throws {
        defer { removeFolder() }
        let transport = StubTransport([Self.reserved(operations: Self.onePart), .ok(""), Self.committed])
        let uploader = try LibraryUploader(client: ASCClient.stubbed(transport: transport))

        let committed = try await uploader.upload(item("one.png"), libraryID: "lib1")

        #expect(committed.assetID == "img1")
        let requests = await transport.requests
        #expect(requests.map(\.httpMethod) == ["POST", "PUT", "PATCH"])
        #expect(requests[0].url?.path == "/v1/appAssetLibraryImages")
        #expect(requests[2].url?.path == "/v1/appAssetLibraryImages/img1")

        let reserve = try #require(try LibraryJSON.body(of: requests[0])["data"] as? NSDictionary)
        let attributes = try #require(reserve["attributes"] as? NSDictionary)
        #expect(attributes["fileName"] as? String == "one.png")
        #expect(attributes["fileSize"] as? Int == 3000)

        let commit = try #require(try LibraryJSON.body(of: requests[2])["data"] as? NSDictionary)
        #expect(commit["attributes"] as? NSDictionary == ["uploaded": true])
    }

    @Test func sendsTheHeadersAndNoTokenToTheUploadAddress() async throws {
        defer { removeFolder() }
        let transport = StubTransport([Self.reserved(operations: Self.onePart), .ok(""), Self.committed])
        let uploader = try LibraryUploader(client: ASCClient.stubbed(transport: transport))

        _ = try await uploader.upload(item("one.png"), libraryID: "lib1")

        let part = await transport.request(at: 1)
        #expect(part.value(forHTTPHeaderField: "Content-Type") == "image/png")
        #expect(part.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test func sendsTheRightSliceForEachOfManyParts() async throws {
        defer { removeFolder() }
        let transport = StubTransport(routes: [
            ("/v1/appAssetLibraryImages/img1", Self.committed),
            ("/v1/appAssetLibraryImages", Self.reserved(operations: Self.twoParts)),
            ("/a", .ok("")), ("/b", .ok(""))
        ])
        let uploader = try LibraryUploader(client: ASCClient.stubbed(transport: transport))

        _ = try await uploader.upload(item("one.png"), libraryID: "lib1")

        let parts = await transport.requests.filter { $0.url?.host == "blob.example.test" }
        let sizes = Dictionary(uniqueKeysWithValues: parts.map { ($0.url!.path, $0.httpBody?.count) })
        #expect(sizes == ["/a": 1000, "/b": 2000])
    }

    @Test func sendsAFailedPartOnceMore() async throws {
        defer { removeFolder() }
        let transport = StubTransport([
            Self.reserved(operations: Self.onePart), .failure(503), .ok(""), Self.committed
        ])
        let uploader = try LibraryUploader(client: ASCClient.stubbed(transport: transport))

        _ = try await uploader.upload(item("one.png"), libraryID: "lib1")

        let methods = await transport.requests.map(\.httpMethod)
        #expect(methods == ["POST", "PUT", "PUT", "PATCH"])
    }

    @Test func givesUpOnAPartThatFailsTwice() async throws {
        defer { removeFolder() }
        let transport = StubTransport([Self.reserved(operations: Self.onePart), .failure(503), .failure(503)])
        let uploader = try LibraryUploader(client: ASCClient.stubbed(transport: transport))

        await #expect(throws: ASCError.self) { try await uploader.upload(item("one.png"), libraryID: "lib1") }
        #expect(await transport.requestCount == 3, "no commit after a part that never arrived")
    }

    @Test func neverSendsAgainAPartThatWasRefused() async throws {
        defer { removeFolder() }
        let transport = StubTransport([Self.reserved(operations: Self.onePart), .failure(403)])
        let uploader = try LibraryUploader(client: ASCClient.stubbed(transport: transport))

        await #expect(throws: ASCError.self) { try await uploader.upload(item("one.png"), libraryID: "lib1") }
        #expect(await transport.requestCount == 2)
    }

    @Test func reportsACommitRefusedForTheWrongSize() async throws {
        defer { removeFolder() }
        let refusal = """
        {"errors":[{"status":"409","code":"ENTITY_ERROR","detail":"The file size does not match."}]}
        """
        let transport = StubTransport([Self.reserved(operations: Self.onePart), .ok(""), .failure(409, refusal)])
        let uploader = try LibraryUploader(client: ASCClient.stubbed(transport: transport))

        let error = await #expect(throws: ASCError.self) { try await uploader.upload(item("one.png"), libraryID: "lib1") }
        #expect(try String(describing: #require(error)).contains("The file size does not match."))
    }

    @Test func refusesAReservationWithNoInstructions() async throws {
        defer { removeFolder() }
        let transport = StubTransport([Self.reserved(operations: "")])
        let uploader = try LibraryUploader(client: ASCClient.stubbed(transport: transport))

        await #expect(throws: UploadError.self) { try await uploader.upload(item("one.png"), libraryID: "lib1") }
    }

    @Test func refusesAPartPastTheEndOfTheFile() async throws {
        defer { removeFolder() }
        let past = #"{"method":"PUT","url":"https://blob.example.test/x","length":5000,"offset":0,"requestHeaders":[]}"#
        let transport = StubTransport([Self.reserved(operations: past)])
        let uploader = try LibraryUploader(client: ASCClient.stubbed(transport: transport))

        await #expect(throws: UploadError.self) { try await uploader.upload(item("one.png"), libraryID: "lib1") }
    }

    @Test func reservesAVideoAtTheVideoAddressWithItsPosterFrame() async throws {
        defer { removeFolder() }
        let transport = StubTransport([Self.reserved(operations: Self.onePart), .ok(""), Self.committed])
        let uploader = try LibraryUploader(client: ASCClient.stubbed(transport: transport))
        let video = try LibraryUploader.Item(
            fileURL: file("preview.mov"), media: .video, category: .screenshotsAndPreviews,
            referenceName: "Preview", previewFrameTimeCode: "00:00:02:00"
        )

        _ = try await uploader.upload(video, libraryID: "lib1")

        let requests = await transport.requests
        #expect(requests[0].url?.path == "/v1/appAssetLibraryVideos")
        #expect(requests[2].url?.path == "/v1/appAssetLibraryVideos/img1")
        let attributes = try #require(try (LibraryJSON.body(of: requests[0])["data"] as? NSDictionary)?["attributes"] as? NSDictionary)
        #expect(attributes["previewFrameTimeCode"] as? String == "00:00:02:00")
        #expect(attributes["referenceName"] as? String == "Preview")
    }

    // MARK: - Many files

    @Test(arguments: [1, 2, 4])
    func uploadsNoMoreFilesAtOnceThanTheLimit(limit: Int) async throws {
        defer { removeFolder() }
        let transport = CountingTransport { _ in .ok("") }
        let uploader = try LibraryUploader(client: ASCClient.stubbed(transport: transport))
        let items = try (1 ... 8).map { try item("file-\($0).png", bytes: 10) }

        let results = await uploader.upload(items, libraryID: "lib1", limit: limit)

        #expect(results.count == 8)
        #expect(results.values.allSatisfy { (try? $0.get()) != nil })
        // Each upload has one request open at a time, so the most open is the
        // most uploads at once.
        #expect(await transport.mostOpen <= limit)
        #expect(await transport.mostOpen == limit, "the limit is also used, not only kept")
    }

    @Test func keepsGoingWhenOneFileFails() async throws {
        defer { removeFolder() }
        let transport = CountingTransport { request in
            request.url?.path == "/file-2" ? .failure(403) : .ok("")
        }
        let uploader = try LibraryUploader(client: ASCClient.stubbed(transport: transport))
        let items = try (1 ... 3).map { try item("file-\($0).png", bytes: 10) }

        let results = await uploader.upload(items, libraryID: "lib1")

        let failed = results.filter { (try? $0.value.get()) == nil }.map(\.key.fileName)
        #expect(failed == ["file-2.png"])
        #expect(try results[items[0]]?.get().assetID == "id-file-1")
    }

    @Test func toldEachCommitAsItHappens() async throws {
        defer { removeFolder() }
        let transport = CountingTransport { _ in .ok("") }
        let uploader = try LibraryUploader(client: ASCClient.stubbed(transport: transport))
        let items = try (1 ... 3).map { try item("file-\($0).png", bytes: 10) }
        let seen = Seen()

        _ = await uploader.upload(items, libraryID: "lib1", onCommit: { await seen.add($0.assetID) })

        #expect(await seen.ids.sorted() == ["id-file-1", "id-file-2", "id-file-3"])
    }

    @Test func uploadsNothingForAnEmptyList() async throws {
        let transport = StubTransport([])
        let uploader = try LibraryUploader(client: ASCClient.stubbed(transport: transport))

        #expect(await uploader.upload([], libraryID: "lib1").isEmpty)
        #expect(await transport.requestCount == 0)
    }

    // MARK: - Waiting for Apple

    static func assets(_ media: String, _ states: [(String, String)]) -> StubTransport.Reply {
        let type = media == "images" ? "appAssetLibraryImages" : "appAssetLibraryVideos"
        let list = states.map { id, state in
            #"{"type":"\#(type)","id":"\#(id)","attributes":{"state":"\#(state)","#
                + #""stateDetails":[{"code":"BAD","description":"Too small."}]}}"#
        }
        return .ok(#"{"data":[\#(list.joined(separator: ","))]}"#)
    }

    @Test func asksAboutEveryAssetOfAKindInOneCall() async throws {
        let transport = StubTransport(routes: [
            ("/images", Self.assets("images", [("a", "PREPARE_FOR_SUBMISSION"), ("b", "PREPARE_FOR_SUBMISSION")])),
            ("/videos", Self.assets("videos", [("v", "PREPARE_FOR_SUBMISSION")]))
        ])
        let uploader = try LibraryUploader(client: ASCClient.stubbed(transport: transport))

        let states = try await uploader.waitUntilProcessed(
            [.image: ["a", "b"], .video: ["v"]], libraryID: "lib1", poll: .immediate
        )

        #expect(states.keys.sorted() == ["a", "b", "v"])
        let requests = await transport.requests
        #expect(requests.count == 2)
        let imageQuery = try LibraryJSON.query(of: #require(requests.first { $0.url?.path.hasSuffix("/images") == true }))
        #expect(imageQuery["filter[id]"] == "a,b")
    }

    @Test func asksAgainOnlyAboutTheOnesStillProcessing() async throws {
        let transport = StubTransport([
            Self.assets("images", [("a", "PREPARE_FOR_SUBMISSION"), ("b", "UPLOAD_COMPLETE")]),
            Self.assets("images", [("b", "FAILED")])
        ])
        let uploader = try LibraryUploader(client: ASCClient.stubbed(transport: transport))

        let states = try await uploader.waitUntilProcessed([.image: ["a", "b"]], libraryID: "lib1", poll: .immediate)

        #expect(states["a"]?.attributes?.state == .prepareForSubmission)
        #expect(states["b"]?.attributes?.state == .failed)
        #expect(await LibraryQuery.ids(in: transport.request(at: 1)) == "b")
    }

    @Test func handsBackAFailureWithApplesReason() async throws {
        let transport = StubTransport(Self.assets("images", [("a", "FAILED")]))
        let uploader = try LibraryUploader(client: ASCClient.stubbed(transport: transport))

        let states = try await uploader.waitUntilProcessed([.image: ["a"]], libraryID: "lib1", poll: .immediate)
        let failed = try #require(states["a"])

        let error = LibraryUploader.Committed.failure(fileName: "one.png", asset: failed)
        #expect(String(describing: error).contains("Too small."))
    }

    @Test func stopsAskingAfterTheLastAttempt() async throws {
        let transport = StubTransport(routes: [
            ("/images", Self.assets("images", [("a", "UPLOAD_COMPLETE")]))
        ])
        let uploader = try LibraryUploader(client: ASCClient.stubbed(transport: transport))

        let states = try await uploader.waitUntilProcessed([.image: ["a"]], libraryID: "lib1", poll: .immediate)

        #expect(states["a"]?.attributes?.state == .uploadComplete)
        #expect(await transport.requestCount == LibraryUploader.PollSettings.immediate.attempts)
    }

    @Test func keepsAskingAboutAnAssetTheAnswerLeftOut() async throws {
        let transport = StubTransport([
            .ok(#"{"data":[]}"#),
            Self.assets("images", [("a", "PREPARE_FOR_SUBMISSION")])
        ])
        let uploader = try LibraryUploader(client: ASCClient.stubbed(transport: transport))

        let states = try await uploader.waitUntilProcessed([.image: ["a"]], libraryID: "lib1", poll: .immediate)

        #expect(states["a"]?.attributes?.state == .prepareForSubmission)
    }

    @Test func asksNothingWhenThereIsNothingToWaitFor() async throws {
        let transport = StubTransport([])
        let uploader = try LibraryUploader(client: ASCClient.stubbed(transport: transport))

        #expect(try await uploader.waitUntilProcessed([.image: []], libraryID: "lib1", poll: .immediate).isEmpty)
        #expect(await transport.requestCount == 0)
    }
}

actor Seen {
    private(set) var ids: [String] = []
    func add(_ id: String) {
        ids.append(id)
    }
}

enum LibraryQuery {
    static func ids(in request: URLRequest) -> String? {
        LibraryJSON.query(of: request)["filter[id]"]
    }
}
