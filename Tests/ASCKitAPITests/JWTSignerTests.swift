import ASCKitTestSupport
import CryptoKit
import Foundation
import Testing
@testable import ASCKitAPI

/// The signature is randomised, so these tests check the header and the claims
/// exactly and check the signature by verifying it, not by comparing bytes.
struct JWTSignerTests {
    let issuedAt = Date(timeIntervalSince1970: 1_700_000_000)

    func decodeSegment(_ token: String, at index: Int) throws -> [String: Any] {
        let segments = token.split(separator: ".", omittingEmptySubsequences: false)
        let data = try #require(Data(base64URLEncoded: String(segments[index])))
        return try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func makeSigner(kind: APIKey.Kind) throws -> JWTSigner {
        try JWTSigner(key: APIKey(id: TestKeys.keyID, kind: kind, privateKeyPEM: TestKeys.privateKeyPEM))
    }

    @Test func readsApplesPKCS8PrivateKey() throws {
        _ = try makeSigner(kind: .team(issuerID: TestKeys.issuerID))
    }

    @Test func rejectsAPrivateKeyItCannotRead() {
        #expect(throws: JWTSignerError.self) {
            try JWTSigner(key: APIKey(id: "X", kind: .individual, privateKeyPEM: "not a key"))
        }
    }

    @Test func headerNamesES256AndTheKeyID() throws {
        let signer = try makeSigner(kind: .team(issuerID: TestKeys.issuerID))
        let token = try signer.token(issuedAt: issuedAt, expiresAt: issuedAt.addingTimeInterval(600))
        let header = try decodeSegment(token, at: 0)

        #expect(header["alg"] as? String == "ES256")
        #expect(header["typ"] as? String == "JWT")
        #expect(header["kid"] as? String == TestKeys.keyID)
    }

    @Test func teamKeyCarriesTheIssuerInISS() throws {
        let signer = try makeSigner(kind: .team(issuerID: TestKeys.issuerID))
        let token = try signer.token(issuedAt: issuedAt, expiresAt: issuedAt.addingTimeInterval(600))
        let claims = try decodeSegment(token, at: 1)

        #expect(claims["iss"] as? String == TestKeys.issuerID)
        #expect(claims["sub"] == nil)
        #expect(claims["aud"] as? String == "appstoreconnect-v1")
        #expect(claims["iat"] as? Int == 1_700_000_000)
        #expect(claims["exp"] as? Int == 1_700_000_600)
    }

    /// Apple: "Individual keys don't use the Issuer ID key iss, but do require
    /// the Subject key sub", whose value is always the literal string "user".
    @Test func individualKeyCarriesUserInSUBAndNoISS() throws {
        let signer = try makeSigner(kind: .individual)
        let token = try signer.token(issuedAt: issuedAt, expiresAt: issuedAt.addingTimeInterval(600))
        let claims = try decodeSegment(token, at: 1)

        #expect(claims["sub"] as? String == "user")
        #expect(claims["iss"] == nil)
    }

    @Test func omitsScopeWhenThereIsNone() throws {
        let signer = try makeSigner(kind: .individual)
        let token = try signer.token(issuedAt: issuedAt, expiresAt: issuedAt.addingTimeInterval(600))
        #expect(try decodeSegment(token, at: 1)["scope"] == nil)
    }

    @Test func carriesScopeWhenGiven() throws {
        let signer = try makeSigner(kind: .individual)
        let token = try signer.token(
            issuedAt: issuedAt,
            expiresAt: issuedAt.addingTimeInterval(600),
            scope: ["GET /v1/apps"]
        )
        #expect(try decodeSegment(token, at: 1)["scope"] as? [String] == ["GET /v1/apps"])
    }

    @Test func signatureVerifiesAgainstThePublicKey() throws {
        let signer = try makeSigner(kind: .team(issuerID: TestKeys.issuerID))
        let token = try signer.token(issuedAt: issuedAt, expiresAt: issuedAt.addingTimeInterval(600))

        let segments = token.split(separator: ".", omittingEmptySubsequences: false)
        #expect(segments.count == 3)

        let signingInput = Data("\(segments[0]).\(segments[1])".utf8)
        let rawSignature = try #require(Data(base64URLEncoded: String(segments[2])))
        #expect(rawSignature.count == 64, "ES256 wants r || s, 32 bytes each")

        let signature = try P256.Signing.ECDSASignature(rawRepresentation: rawSignature)
        #expect(signer.publicKey.isValidSignature(signature, for: signingInput))
    }

    @Test func tokenCarriesNoBase64Padding() throws {
        let signer = try makeSigner(kind: .team(issuerID: TestKeys.issuerID))
        let token = try signer.token(issuedAt: issuedAt, expiresAt: issuedAt.addingTimeInterval(600))
        #expect(token.contains("=") == false)
        #expect(token.contains("+") == false)
        #expect(token.contains("/") == false)
    }

    @Test func rejectsALifetimeAppleWouldRefuse() throws {
        let signer = try makeSigner(kind: .individual)
        #expect(throws: JWTSignerError.lifetimeTooLong(requested: 1201, maximum: 1200)) {
            try signer.token(issuedAt: issuedAt, expiresAt: issuedAt.addingTimeInterval(1201))
        }
    }

    @Test func acceptsExactlyTwentyMinutes() throws {
        let signer = try makeSigner(kind: .individual)
        _ = try signer.token(issuedAt: issuedAt, expiresAt: issuedAt.addingTimeInterval(1200))
    }

    @Test(arguments: [0.0, -1.0, -600.0])
    func rejectsAnExpiryThatIsNotInTheFuture(offset: TimeInterval) throws {
        let signer = try makeSigner(kind: .individual)
        #expect(throws: JWTSignerError.expiryNotInTheFuture) {
            try signer.token(issuedAt: issuedAt, expiresAt: issuedAt.addingTimeInterval(offset))
        }
    }
}
