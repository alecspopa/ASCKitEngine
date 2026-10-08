import ASCKitAPI
import Foundation
import Testing
@testable import ASCKitProject

final class PrivateKeyStoreTests {
    let fixture: FixtureProject
    let keyID = "2X9R4HXF34"

    init() throws {
        fixture = try FixtureProject()
    }

    deinit {
        fixture.remove()
    }

    /// A throwaway P-256 key in the PKCS#8 shape Apple hands out. It
    /// authenticates nothing.
    let pem = """
    -----BEGIN PRIVATE KEY-----
    MIGHAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBG0wawIBAQQg+93IOlpopuMCvKOT
    j6JmNQEck99p7mHrx3jo+EDDe+yhRANCAARftryy4A6MuhdolnijBx83+mQiDheD
    drEgWMok4f86ZodnPWLtc8KoBNNzxarAKlGH2CCIWLgBIawSpuaYovQt
    -----END PRIVATE KEY-----
    """

    @discardableResult
    func writeKey(named name: String? = nil, in folder: String = "keys") throws -> URL {
        let directory = fixture.rootURL.appending(path: folder)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: name ?? PrivateKeyStore.fileName(for: keyID))
        try Data(pem.utf8).write(to: url)
        return url
    }

    func config(issuerID: String? = "issuer") -> ProjectConfig {
        ProjectConfig(bundleID: "com.example.MyApp", keyID: keyID, issuerID: issuerID)
    }

    // MARK: - Finding

    @Test func findsTheKeyByTheNameAppleGivesIt() throws {
        try writeKey()
        let found = PrivateKeyStore.locate(
            keyID: keyID,
            environment: [:],
            directories: [fixture.rootURL.appending(path: "keys")]
        )
        #expect(found?.lastPathComponent == "AuthKey_2X9R4HXF34.p8")
    }

    @Test func findsNothingWhenTheKeyIsNotThere() {
        #expect(PrivateKeyStore.locate(
            keyID: keyID,
            environment: [:],
            directories: [fixture.rootURL]
        ) == nil)
    }

    /// So a key kept somewhere else still works without moving it.
    @Test func anExplicitPathWinsOverTheSearchDirectories() throws {
        let elsewhere = try writeKey(named: "somewhere-else.p8", in: "custom")
        try writeKey()

        let found = PrivateKeyStore.locate(
            keyID: keyID,
            environment: [PrivateKeyStore.environmentVariable: elsewhere.path],
            directories: [fixture.rootURL.appending(path: "keys")]
        )
        #expect(found == elsewhere)
    }

    @Test func findsNothingWhenTheExplicitPathIsWrong() throws {
        try writeKey()
        #expect(PrivateKeyStore.locate(
            keyID: keyID,
            environment: [PrivateKeyStore.environmentVariable: "/nowhere/AuthKey_X.p8"],
            directories: [fixture.rootURL.appending(path: "keys")]
        ) == nil)
    }

    @Test func searchesTheSameFoldersApplesToolsDo() {
        let home = URL(fileURLWithPath: "/Users/someone")
        let working = URL(fileURLWithPath: "/work")
        let paths = PrivateKeyStore.searchDirectories(home: home, workingDirectory: working).map(\.path)

        #expect(paths == [
            "/work/private_keys",
            "/Users/someone/private_keys",
            "/Users/someone/.private_keys",
            "/Users/someone/.appstoreconnect/private_keys"
        ])
    }

    // MARK: - Building the key

    /// An issuer id means a team key. Without one it is an individual key, and
    /// the token identifies itself differently.
    @Test func makesATeamKeyWhenThereIsAnIssuerID() throws {
        try writeKey()
        let key = try PrivateKeyStore.apiKey(
            for: config(issuerID: "the-issuer"),
            environment: [:],
            directories: [fixture.rootURL.appending(path: "keys")]
        )
        #expect(key.kind == .team(issuerID: "the-issuer"))
        #expect(key.id == keyID)
    }

    @Test func makesAnIndividualKeyWhenThereIsNoIssuerID() throws {
        try writeKey()
        let key = try PrivateKeyStore.apiKey(
            for: config(issuerID: nil),
            environment: [:],
            directories: [fixture.rootURL.appending(path: "keys")]
        )
        #expect(key.kind == .individual)
    }

    /// The key it finds has to be one the signer can actually use.
    @Test func producesAKeyTheSignerAccepts() throws {
        try writeKey()
        let key = try PrivateKeyStore.apiKey(
            for: config(),
            environment: [:],
            directories: [fixture.rootURL.appending(path: "keys")]
        )
        _ = try JWTSigner(key: key)
    }

    @Test func explainsHowToMakeAKeyWhenThereIsNone() throws {
        let error = #expect(throws: PrivateKeyError.self) {
            try PrivateKeyStore.apiKey(
                for: config(),
                environment: [:],
                directories: [fixture.rootURL]
            )
        }
        let text = try String(describing: #require(error))
        #expect(text.contains("App Manager role"))
        #expect(text.contains("AuthKey_2X9R4HXF34.p8"))
        #expect(text.contains(fixture.rootURL.path))
    }

    // MARK: - Permissions

    @Test func noticesAKeyOtherAccountsCanRead() throws {
        let url = try writeKey()
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: url.path)
        #expect(PrivateKeyStore.isReadableByOthers(url: url))
    }

    @Test func saysNothingAboutAKeyOnlyTheOwnerCanRead() throws {
        let url = try writeKey()
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        #expect(PrivateKeyStore.isReadableByOthers(url: url) == false)
    }

    // MARK: - Reading a picked file

    @Test func readsTheKeyIDFromAPickedFile() throws {
        let picked = try PrivateKeyStore.readKey(pem: pem, fileName: "AuthKey_2X9R4HXF34.p8")
        #expect(picked == PickedKey(fileName: "AuthKey_2X9R4HXF34.p8", keyID: keyID, pem: pem))
    }

    /// Picking the wrong file is easy. Saying so now beats a request that fails
    /// later and looks like a network problem.
    @Test func refusesAFileThatIsNotAPrivateKey() {
        #expect(throws: CredentialError.notAPrivateKey(fileName: "notes.txt")) {
            try PrivateKeyStore.readKey(pem: "just some text", fileName: "notes.txt")
        }
    }

    @Test func refusesAKeyThatCannotSign() {
        let broken = "-----BEGIN PRIVATE KEY-----\nnot base64\n-----END PRIVATE KEY-----"
        #expect(throws: (any Error).self) {
            try PrivateKeyStore.readKey(pem: broken, fileName: "AuthKey_2X9R4HXF34.p8")
        }
    }

    // MARK: - Installing

    @Test func installsAKeyWhereTheLookupFindsIt() throws {
        let directory = fixture.rootURL.appending(path: "private_keys")
        let picked = PickedKey(fileName: "AuthKey_2X9R4HXF34.p8", keyID: keyID, pem: pem)

        let url = try PrivateKeyStore.install(picked, keyID: keyID, into: directory)

        #expect(url.lastPathComponent == "AuthKey_2X9R4HXF34.p8")
        let key = try PrivateKeyStore.apiKey(for: config(), environment: [:], directories: [directory])
        #expect(key.privateKeyPEM == pem)
    }

    @Test func installsAKeyOnlyTheOwnerCanRead() throws {
        let picked = PickedKey(fileName: "key.p8", keyID: nil, pem: pem)
        let url = try PrivateKeyStore.install(picked, keyID: keyID, into: fixture.rootURL)
        #expect(PrivateKeyStore.isReadableByOthers(url: url) == false)
    }

    /// A file that was already there with loose permissions gets tight ones.
    @Test func tightensTheKeyItReplaces() throws {
        let existing = try writeKey()
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: existing.path)

        let picked = PickedKey(fileName: "key.p8", keyID: nil, pem: pem)
        let url = try PrivateKeyStore.install(picked, keyID: keyID, into: existing.deletingLastPathComponent())

        #expect(url == existing)
        #expect(PrivateKeyStore.isReadableByOthers(url: url) == false)
    }

    @Test func refusesToInstallAKeyUnderAnotherKeyID() throws {
        let picked = PickedKey(fileName: "AuthKey_D5S334FLQQ.p8", keyID: "D5S334FLQQ", pem: pem)
        let expected = CredentialError.wrongKey(
            fileName: "AuthKey_D5S334FLQQ.p8", expected: keyID, found: "D5S334FLQQ"
        )

        #expect(throws: expected) {
            try PrivateKeyStore.install(picked, keyID: keyID, into: fixture.rootURL)
        }
        #expect(FileManager.default.fileExists(
            atPath: fixture.rootURL.appending(path: PrivateKeyStore.fileName(for: keyID)).path
        ) == false)
    }

    // MARK: - Which key a file name names

    /// Apple names the file after the key inside it, and the bytes say nothing
    /// about which key they are. So the name is what tells two keys apart.
    @Test(arguments: [
        ("AuthKey_2X9R4HXF34.p8", "2X9R4HXF34"),
        ("AuthKey_D5S334FLQQ.p8", "D5S334FLQQ")
    ])
    func readsTheKeyIDOutOfApplesFileName(name: String, expected: String) {
        #expect(PrivateKeyStore.keyID(fromFileName: name) == expected)
    }

    @Test(arguments: ["key.p8", "AuthKey_2X9R4HXF34.pem", "AuthKey_.p8", "AuthKey_2X9R4HXF34"])
    func tellsNothingFromANameAppleDidNotWrite(name: String) {
        #expect(PrivateKeyStore.keyID(fromFileName: name) == nil)
    }
}
