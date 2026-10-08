import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// Talks to App Store Connect.
///
/// A value type rather than an actor, so several uploads can run at once. The
/// only shared mutable state is the cached token, and that lives in its own
/// actor.
public struct ASCClient: Sendable {
    public static let productionBaseURL = URL(string: "https://api.appstoreconnect.apple.com")!

    let transport: any Transport
    private let tokens: TokenProvider
    private let baseURL: URL
    private let retryPolicy: RetryPolicy

    /// Read once at build time, so a 401 can name the shape of the token that
    /// was refused without waiting on the actor that signs it.
    private let signsIndividualKey: Bool

    /// Shared by every copy of this client, so one refusal slows all of the
    /// requests it is making rather than only the one that was refused.
    private let gate = RateLimitGate()

    /// Told how long a wait is, so a window can say why it is doing nothing
    /// instead of showing a spinner for a minute. Told nil when the wait is
    /// over.
    private var onWait: (@Sendable (Duration?) -> Void)?

    public init(
        key: APIKey,
        transport: any Transport = URLSessionTransport(),
        baseURL: URL = productionBaseURL,
        retryPolicy: RetryPolicy = RetryPolicy()
    ) throws {
        try self.init(
            tokens: TokenProvider(key: key),
            transport: transport,
            baseURL: baseURL,
            retryPolicy: retryPolicy
        )
    }

    public init(
        tokens: TokenProvider,
        transport: any Transport = URLSessionTransport(),
        baseURL: URL = productionBaseURL,
        retryPolicy: RetryPolicy = RetryPolicy()
    ) {
        self.tokens = tokens
        self.transport = transport
        self.baseURL = baseURL
        self.retryPolicy = retryPolicy
        signsIndividualKey = tokens.signsIndividualKey
    }

    /// The same client, saying out loud when App Store Connect tells it to
    /// wait and again when the wait is over. The gate is shared with the copy,
    /// so both hold the one wait.
    public func reportingWaits(to notice: @escaping @Sendable (Duration?) -> Void) -> ASCClient {
        var copy = self
        copy.onWait = notice
        return copy
    }

    // MARK: - Reading

    func get<Attributes: Decodable & Sendable>(
        _ path: String,
        query: [URLQueryItem] = [],
        as type: Attributes.Type = Attributes.self
    ) async throws -> Resource<Attributes> {
        let data = try await send(method: "GET", url: url(path, query: query), body: nil).0
        return try decode(SingleResponse<Attributes>.self, from: data).data
    }

    /// Follows `links.next` to the end, so the caller never sees a page.
    func list<Attributes: Decodable & Sendable>(
        _ path: String,
        query: [URLQueryItem] = [],
        as type: Attributes.Type = Attributes.self
    ) async throws -> [Resource<Attributes>] {
        var next: URL? = url(path, query: query)
        var collected: [Resource<Attributes>] = []

        while let current = next {
            let data = try await send(method: "GET", url: current, body: nil).0
            let page = try decode(ListResponse<Attributes>.self, from: data)
            collected.append(contentsOf: page.data)
            next = page.links?.next.flatMap(URL.init(string:))
        }
        return collected
    }

    /// The same, keeping what `include` brought along.
    ///
    /// Follows `links.next` like `list` does. Reading one page here would lose
    /// countries silently: a subscription's prices run to two rows per country,
    /// so 175 countries is 350 rows and a 200-row page drops half of them with
    /// no sign that anything is missing.
    func listIncluding<Attributes: Decodable & Sendable>(
        _ path: String,
        query: [URLQueryItem] = [],
        as type: Attributes.Type = Attributes.self
    ) async throws -> (data: [Resource<Attributes>], included: [Resource<Attributes>]) {
        var next: URL? = url(path, query: query)
        var data: [Resource<Attributes>] = []
        var included: [Resource<Attributes>] = []

        while let current = next {
            let raw = try await send(method: "GET", url: current, body: nil).0
            let page = try decode(ListResponse<Attributes>.self, from: raw)
            data += page.data
            included += page.included ?? []
            next = page.links?.next.flatMap(URL.init(string:))
        }
        return (data, included)
    }

    /// The same, for an `include` that brings back resources of another kind.
    func listMixed<Attributes: Decodable & Sendable, Included: Decodable & Sendable>(
        _ path: String,
        query: [URLQueryItem] = [],
        as type: Attributes.Type = Attributes.self,
        including includedType: Included.Type = Included.self
    ) async throws -> (data: [Resource<Attributes>], included: [Resource<Included>]) {
        var next: URL? = url(path, query: query)
        var data: [Resource<Attributes>] = []
        var included: [Resource<Included>] = []

        while let current = next {
            let raw = try await send(method: "GET", url: current, body: nil).0
            let page = try decode(MixedListResponse<Attributes, Included>.self, from: raw)
            data += page.data
            included += page.included ?? []
            next = page.links?.next.flatMap(URL.init(string:))
        }
        return (data, included)
    }

    // MARK: - Writing

    func post<Attributes: Decodable & Sendable>(
        _ path: String,
        body: WriteRequest<some Encodable & Sendable>,
        as type: Attributes.Type = Attributes.self
    ) async throws -> Resource<Attributes> {
        let data = try await send(method: "POST", url: url(path), body: encode(body)).0
        return try decode(SingleResponse<Attributes>.self, from: data).data
    }

    /// A create whose body carries the resources it points at.
    ///
    /// Only a price schedule needs this. Everything else goes through `post`,
    /// where the relationships name things that already exist.
    func post<Attributes: Decodable & Sendable>(
        _ path: String,
        compound body: CompoundWriteRequest<some Encodable & Sendable>,
        as type: Attributes.Type = Attributes.self
    ) async throws -> Resource<Attributes> {
        let data = try await send(method: "POST", url: url(path), body: encode(body)).0
        return try decode(SingleResponse<Attributes>.self, from: data).data
    }

    /// A change whose body carries the resources it points at.
    ///
    /// A subscription's prices go this way: they do not exist yet, so they
    /// travel in `included` and the subscription's `prices` relationship points
    /// at their local ids.
    func patch<Attributes: Decodable & Sendable>(
        _ path: String,
        compound body: CompoundWriteRequest<some Encodable & Sendable>,
        as type: Attributes.Type = Attributes.self
    ) async throws -> Resource<Attributes> {
        let data = try await send(method: "PATCH", url: url(path), body: encode(body)).0
        return try decode(SingleResponse<Attributes>.self, from: data).data
    }

    func patch<Attributes: Decodable & Sendable>(
        _ path: String,
        body: WriteRequest<some Encodable & Sendable>,
        as type: Attributes.Type = Attributes.self
    ) async throws -> Resource<Attributes> {
        let data = try await send(method: "PATCH", url: url(path), body: encode(body)).0
        return try decode(SingleResponse<Attributes>.self, from: data).data
    }

    func delete(_ path: String) async throws {
        _ = try await send(method: "DELETE", url: url(path), body: nil)
    }

    /// Relationship updates answer 204 with no body, so they decode nothing.
    func replaceRelationship(_ path: String, with identifiers: [Identifier]) async throws {
        let body = try encode(RelationshipToMany(data: identifiers))
        _ = try await send(method: "PATCH", url: url(path), body: body)
    }

    // MARK: - The one place a request actually happens

    @discardableResult
    func send(method: String, url: URL, body: Data?) async throws -> (Data, RateLimit?) {
        var lastError: (any Error)?
        var waitedOutARateLimit = false

        // However this ends, nothing is waiting on a rate limit any more.
        var saidItIsWaiting = false
        defer { if saidItIsWaiting { onWait?(nil) } }

        for attempt in 1 ... max(1, retryPolicy.maximumAttempts) {
            let pause = retryPolicy.delay(beforeAttempt: attempt)
            if pause > .zero { try await Task.sleep(for: pause) }
            try await gate.waitUntilOpen()

            if saidItIsWaiting {
                saidItIsWaiting = false
                onWait?(nil)
            }
            try Task.checkCancellation()

            do {
                return try await sendOnce(method: method, url: url, body: body)
            } catch let error as ASCError where error.isWorthRetrying {
                if let wait = Self.statedWait(in: error) {
                    // Once. A second refusal that names another wait is App
                    // Store Connect saying come back later, not try harder.
                    guard waitedOutARateLimit == false, wait <= retryPolicy.maximumWait else {
                        throw error
                    }
                    waitedOutARateLimit = true
                    saidItIsWaiting = true
                    onWait?(wait)
                    await gate.close(for: wait)
                }
                lastError = error
            } catch let error as ASCError {
                // A refused token is worth exactly one more try with a fresh
                // one. A token refused for having no issuer is not, because the
                // fresh one is signed the same way.
                guard case .unauthorized = error, attempt == 1 else { throw error }
                await tokens.discardCachedToken()
                lastError = error
            }
        }
        throw lastError ?? ASCError.notAnHTTPResponse
    }

    /// How long App Store Connect asked this request to wait, when it said.
    private static func statedWait(in error: ASCError) -> Duration? {
        guard case let .rateLimited(limit, _) = error else { return nil }
        return limit?.retryAfter
    }

    private func sendOnce(method: String, url: URL, body: Data?) async throws -> (Data, RateLimit?) {
        var request = URLRequest(url: url)
        request.httpMethod = method
        try await request.setValue("Bearer \(tokens.token())", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        let (data, response) = try await perform(request)
        let rateLimit = RateLimit(response: response)

        guard (200 ..< 300).contains(response.statusCode) else {
            let failure = ASCError.from(status: response.statusCode, data: data, response: response)
            // A token with no issuer in it is refused for what it says rather
            // than for when it was made, so this one is worth telling apart.
            if case let .unauthorized(details) = failure, signsIndividualKey {
                throw ASCError.unauthorizedIndividualKey(details: details)
            }
            throw failure
        }
        return (data, rateLimit)
    }

    /// The one place a `URLError` becomes something this app can explain.
    ///
    /// Left alone it reaches a person as an `NSError` dump. Every request goes
    /// through here, the screenshot parts included, so none of them can.
    func perform(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        do {
            return try await transport.send(request)
        } catch let error as URLError {
            throw ASCError.transport(error)
        }
    }

    // MARK: - Helpers

    private func url(_ path: String, query: [URLQueryItem] = []) -> URL {
        var components = URLComponents(
            url: baseURL.appending(path: path),
            resolvingAgainstBaseURL: false
        )!
        if query.isEmpty == false { components.queryItems = query }
        return components.url!
    }

    private func encode(_ value: some Encodable & Sendable) throws -> Data {
        try JSONEncoder().encode(value)
    }

    private func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        do {
            return try JSONDecoder().decode(type, from: data)
        } catch {
            throw ASCError.decodingFailed(underlying: error, body: data)
        }
    }
}
