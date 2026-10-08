import Foundation

/// An App Store Connect API key, as issued under Users and Access, Integrations.
///
/// Team keys and individual keys differ only in how the token identifies the
/// caller: a team key carries the issuer id in `iss`, an individual key carries
/// the literal string `user` in `sub` and has no issuer id at all.
public struct APIKey: Sendable, Hashable {
    public enum Kind: Sendable, Hashable {
        case team(issuerID: String)
        case individual
    }

    /// The key id Apple shows next to the key. Becomes the `kid` header field.
    public let id: String
    public let kind: Kind

    /// The contents of the `.p8` file, banners included.
    public let privateKeyPEM: String

    /// Whether the token this key signs names no issuer. App Store Connect
    /// refuses a team key signed that way every time, so a refusal from such a
    /// key names its own likely cause.
    public var isIndividual: Bool { kind == .individual }

    public init(id: String, kind: Kind, privateKeyPEM: String) {
        self.id = id
        self.kind = kind
        self.privateKeyPEM = privateKeyPEM
    }
}
