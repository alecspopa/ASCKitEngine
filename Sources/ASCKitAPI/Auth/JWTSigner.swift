import CryptoKit
import Foundation

/// Signs the ES256 tokens App Store Connect expects on every request.
///
/// CryptoKit reads Apple's `.p8` directly and its signature representation is
/// already the `r || s` pair that ES256 asks for, so this needs no third-party
/// JWT library.
public struct JWTSigner: Sendable {
    /// Apple rejects any token that expires more than 20 minutes into the future.
    public static let maximumLifetime: TimeInterval = 20 * 60

    public static let audience = "appstoreconnect-v1"

    private let key: APIKey
    private let privateKey: P256.Signing.PrivateKey

    /// Parses the key once, so a malformed `.p8` fails here rather than on the
    /// first request, where it would look like a network problem.
    public init(key: APIKey) throws {
        self.key = key
        do {
            privateKey = try P256.Signing.PrivateKey(pemRepresentation: key.privateKeyPEM)
        } catch {
            throw JWTSignerError.unreadablePrivateKey(underlying: error)
        }
    }

    /// The public half, so a caller can check a token it just made.
    public var publicKey: P256.Signing.PublicKey { privateKey.publicKey }

    /// Which of the two shapes the token takes, so a caller that gets a refusal
    /// can say which one was sent.
    public var signsIndividualKey: Bool { key.isIndividual }

    public func token(issuedAt: Date, expiresAt: Date, scope: [String]? = nil) throws -> String {
        let lifetime = expiresAt.timeIntervalSince(issuedAt)
        guard lifetime > 0 else { throw JWTSignerError.expiryNotInTheFuture }
        guard lifetime <= Self.maximumLifetime else {
            throw JWTSignerError.lifetimeTooLong(requested: lifetime, maximum: Self.maximumLifetime)
        }

        let header = Header(kid: key.id)
        var claims = Claims(
            iat: Int(issuedAt.timeIntervalSince1970),
            exp: Int(expiresAt.timeIntervalSince1970),
            aud: Self.audience,
            scope: scope
        )
        switch key.kind {
        case let .team(issuerID): claims.iss = issuerID
        case .individual: claims.sub = "user"
        }

        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let signingInput = try encoder.encode(header).base64URLEncodedString()
            + "."
            + encoder.encode(claims).base64URLEncodedString()
        let signature = try privateKey.signature(for: Data(signingInput.utf8))

        return signingInput + "." + signature.rawRepresentation.base64URLEncodedString()
    }

    /// Convenience for callers that just want a token valid from now.
    public func token(now: Date = .now, lifetime: TimeInterval = maximumLifetime) throws -> String {
        try token(issuedAt: now, expiresAt: now.addingTimeInterval(lifetime))
    }

    private struct Header: Encodable {
        let alg = "ES256"
        let kid: String
        let typ = "JWT"
    }

    private struct Claims: Encodable {
        var iss: String?
        var sub: String?
        let iat: Int
        let exp: Int
        let aud: String
        let scope: [String]?
    }
}

public enum JWTSignerError: Error, Equatable {
    case unreadablePrivateKey(underlying: any Error)
    case expiryNotInTheFuture
    case lifetimeTooLong(requested: TimeInterval, maximum: TimeInterval)

    public static func == (lhs: JWTSignerError, rhs: JWTSignerError) -> Bool {
        switch (lhs, rhs) {
        case (.unreadablePrivateKey, .unreadablePrivateKey): true
        case (.expiryNotInTheFuture, .expiryNotInTheFuture): true
        case let (.lifetimeTooLong(l1, l2), .lifetimeTooLong(r1, r2)): l1 == r1 && l2 == r2
        default: false
        }
    }
}

extension JWTSignerError: CustomLocalizedStringResourceConvertible {
    public var localizedStringResource: LocalizedStringResource {
        switch self {
        case let .unreadablePrivateKey(underlying):
            LocalizedStringResource("""
            ASCKit cannot read the private key. \(ErrorMessage.text(for: underlying))
            """, bundle: .here)
        case .expiryNotInTheFuture:
            LocalizedStringResource("The token would already have expired.", bundle: .here)
        case let .lifetimeTooLong(requested, maximum):
            LocalizedStringResource("""
            A token may last \(Int(maximum)) seconds, and this one asks for \(Int(requested)).
            """, bundle: .here)
        }
    }
}

extension JWTSignerError: CustomStringConvertible {
    public var description: String { String(localized: localizedStringResource) }
}
