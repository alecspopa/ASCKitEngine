import ASCKitAPI
import Foundation

/// Answers canned replies and remembers what it was asked, so the client can be
/// exercised without a network connection.
public actor StubTransport: Transport {
    public struct Reply: Sendable {
        public var status: Int = 200
        var body: Data = .init("{}".utf8)
        public var headers: [String: String] = [:]

        /// Set when the request never gets an answer at all, the way a dropped
        /// connection or a timeout never does.
        var networkError: URLError?

        public init(status: Int = 200, body: Data = Data("{}".utf8), headers: [String: String] = [:]) {
            self.status = status
            self.body = body
            self.headers = headers
        }

        public static func ok(_ json: String, headers: [String: String] = [:]) -> Reply {
            Reply(status: 200, body: Data(json.utf8), headers: headers)
        }

        public static func failure(
            _ status: Int,
            _ json: String = #"{"errors":[]}"#,
            headers: [String: String] = [:]
        ) -> Reply {
            Reply(status: status, body: Data(json.utf8), headers: headers)
        }

        /// No answer. URLSession reports these instead of a status code.
        public static func networkFailure(_ code: URLError.Code) -> Reply {
            var reply = Reply()
            reply.networkError = URLError(code)
            return reply
        }
    }

    private var remaining: [Reply]

    /// Replies chosen by what the request asks for rather than by when it
    /// arrives. Needed whenever the code under test makes calls concurrently,
    /// because then the order they reach the stub in is not decided by anything.
    private var routes: [(match: String, reply: Reply)] = []

    public private(set) var requests: [URLRequest] = []

    public init(_ replies: [Reply]) {
        remaining = replies
    }

    public init(_ reply: Reply) {
        remaining = [reply]
    }

    /// Each entry is a piece of the path and the reply for any request whose
    /// path contains it. First match wins, so put the longer ones first.
    public init(routes: [(String, Reply)]) {
        remaining = []
        self.routes = routes.map { (match: $0.0, reply: $0.1) }
    }

    /// Replies chosen by what is in the body rather than by the path.
    ///
    /// For writes that all go to one address and differ only in what they say,
    /// such as a subscription price, where every country is a POST to the same
    /// place. The last entry is the reply for anything that matches nothing.
    public init(bodyRoutes: [(String, Reply)], otherwise: Reply) {
        remaining = []
        self.bodyRoutes = bodyRoutes.map { (match: $0.0, reply: $0.1) }
        fallback = otherwise
    }

    private var bodyRoutes: [(match: String, reply: Reply)] = []
    private var fallback: Reply?

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)

        if let fallback {
            let body = request.httpBody.flatMap { String(data: $0, encoding: .utf8) } ?? ""
            let route = bodyRoutes.first { body.contains($0.match) }
            return try response(for: route?.reply ?? fallback, request: request)
        }

        if routes.isEmpty == false {
            let path = request.url?.path ?? ""
            guard let route = routes.first(where: { path.contains($0.match) }) else {
                throw StubError.noRouteMatched(path: path)
            }
            return try response(for: route.reply, request: request)
        }

        guard remaining.isEmpty == false else {
            throw StubError.ranOutOfReplies(afterRequests: requests.count)
        }
        let reply = remaining.removeFirst()
        return try response(for: reply, request: request)
    }

    private func response(for reply: Reply, request: URLRequest) throws -> (Data, HTTPURLResponse) {
        if let networkError = reply.networkError { throw networkError }

        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: reply.status,
            httpVersion: "HTTP/1.1",
            headerFields: reply.headers
        )!
        return (reply.body, response)
    }

    public var requestCount: Int { requests.count }

    public func request(at index: Int) -> URLRequest {
        requests[index]
    }

    public enum StubError: Error {
        case ranOutOfReplies(afterRequests: Int)
        case noRouteMatched(path: String)
    }
}

public extension ASCClient {
    /// A client wired to a stub, with retrying turned off unless a test asks.
    static func stubbed(
        transport: any Transport,
        retryPolicy: RetryPolicy = .none,
        kind: APIKey.Kind = .team(issuerID: TestKeys.issuerID)
    ) throws -> ASCClient {
        let key = APIKey(id: TestKeys.keyID, kind: kind, privateKeyPEM: TestKeys.privateKeyPEM)
        return try ASCClient(
            tokens: TokenProvider(key: key),
            transport: transport,
            baseURL: URL(string: "https://api.example.test")!,
            retryPolicy: retryPolicy
        )
    }
}

public extension StubTransport {
    /// Routes for an app whose App Asset Library holds nothing yet. Put them
    /// first in a list of routes, so that `/apps` and
    /// `/appStoreVersionLocalizations` do not answer the library's requests.
    static let emptyLibraryRoutes: [(String, Reply)] = [
        ("/placements", .ok(#"{"data":[]}"#)),
        ("/assetLibrary", .ok(#"{"data":{"type":"appAssetLibraries","id":"lib0"}}"#)),
        ("/appAssetLibraries/lib0/images", .ok(#"{"data":[]}"#)),
        ("/appAssetLibraries/lib0/videos", .ok(#"{"data":[]}"#)),
        ("/appAssetLibraryRefData", .ok(#"{"data":[]}"#))
    ]
}
