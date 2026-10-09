import Foundation

/// Hands out a bearer token, making a new one only when the old one is close to
/// expiring.
///
/// Signing is fast and synchronous, so nothing in here suspends. That is
/// deliberate: an `await` inside would open the door to two callers both
/// deciding the cache is stale.
public actor TokenProvider {
    /// Refresh this long before the real expiry, so a request already in flight
    /// does not arrive with a token that died on the way.
    private static let refreshMargin: TimeInterval = 60

    private let signer: JWTSigner
    private let lifetime: TimeInterval
    private var cached: (token: String, expiresAt: Date)?

    public init(signer: JWTSigner, lifetime: TimeInterval = JWTSigner.maximumLifetime) {
        self.signer = signer
        self.lifetime = lifetime
    }

    public init(key: APIKey, lifetime: TimeInterval = JWTSigner.maximumLifetime) throws {
        try self.init(signer: JWTSigner(key: key), lifetime: lifetime)
    }

    /// The signer is an immutable `Sendable` value, so reading this needs no
    /// hop onto the actor. That matters because the client keeps the answer
    /// from before it makes its first request.
    public nonisolated var signsIndividualKey: Bool { signer.signsIndividualKey }

    public func token(now: Date = .now) throws -> String {
        if let cached, cached.expiresAt.timeIntervalSince(now) > Self.refreshMargin {
            return cached.token
        }
        let expiresAt = now.addingTimeInterval(lifetime)
        let token = try signer.token(issuedAt: now, expiresAt: expiresAt)
        cached = (token, expiresAt)
        return token
    }

    /// For a 401, where the token is the thing under suspicion.
    public func discardCachedToken() {
        cached = nil
    }
}
