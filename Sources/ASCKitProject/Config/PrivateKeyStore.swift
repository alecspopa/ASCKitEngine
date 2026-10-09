import ASCKitAPI
import Foundation

/// Finds the `.p8` private key on disk and turns a project's configuration into
/// something the API layer can authenticate with.
///
/// The key never lives in the project, so it never lands in a repository. Only
/// the key id and the issuer id do, and those are identifiers rather than
/// secrets.
public enum PrivateKeyStore {
    /// Where Apple's own tools look, in the order they look. Keeping the same
    /// order means a key that already works for altool works here too.
    public static func searchDirectories(
        home: URL = URL(fileURLWithPath: NSHomeDirectory()),
        workingDirectory: URL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    ) -> [URL] {
        [
            workingDirectory.appending(path: "private_keys"),
            home.appending(path: "private_keys"),
            home.appending(path: ".private_keys"),
            home.appending(path: ".appstoreconnect").appending(path: "private_keys")
        ]
    }

    /// The one to tell people about, because it is the one Apple documents.
    public static var recommendedDirectory: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appending(path: ".appstoreconnect")
            .appending(path: "private_keys")
    }

    public static func fileName(for keyID: String) -> String {
        "AuthKey_\(keyID).p8"
    }

    /// The key id Apple's own file name carries.
    ///
    /// A `.p8` says nothing about which key is inside it, so the name is the
    /// only thing that does. A file renamed to anything else answers nil,
    /// because then nothing can be told from the name either.
    public static func keyID(fromFileName name: String) -> String? {
        let prefix = "AuthKey_"
        let suffix = ".p8"
        guard name.hasPrefix(prefix), name.hasSuffix(suffix) else { return nil }

        let id = name.dropFirst(prefix.count).dropLast(suffix.count)
        return id.isEmpty ? nil : String(id)
    }

    /// An explicit path always wins, so a key kept somewhere else still works.
    public static let environmentVariable = "ASCKIT_PRIVATE_KEY"

    public static func locate(
        keyID: String,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        directories: [URL]? = nil
    ) -> URL? {
        if let explicit = environment[environmentVariable], explicit.isEmpty == false {
            let url = URL(fileURLWithPath: (explicit as NSString).expandingTildeInPath)
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }

        let name = fileName(for: keyID)
        for directory in directories ?? searchDirectories() {
            let candidate = directory.appending(path: name)
            if FileManager.default.fileExists(atPath: candidate.path) { return candidate }
        }
        return nil
    }

    public static func apiKey(
        for config: ProjectConfig,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        directories: [URL]? = nil
    ) throws -> APIKey {
        guard let url = locate(keyID: config.keyID, environment: environment, directories: directories) else {
            throw PrivateKeyError.notFound(keyID: config.keyID, looked: directories ?? searchDirectories())
        }

        let pem: String
        do {
            pem = try String(contentsOf: url, encoding: .utf8)
        } catch {
            throw PrivateKeyError.unreadable(url: url, underlying: error)
        }

        // No issuer id means an individual key, which identifies itself
        // differently in the token.
        let kind: APIKey.Kind = config.issuerID.map { .team(issuerID: $0) } ?? .individual
        return APIKey(id: config.keyID, kind: kind, privateKeyPEM: pem)
    }

    // MARK: - Keeping a key

    /// Says what is in a `.p8`, and refuses one that cannot sign.
    ///
    /// Proving it signs now beats finding out on the first request, where a
    /// bad key looks exactly like a network problem.
    public static func readKey(pem: String, fileName: String) throws -> PickedKey {
        let named = keyID(fromFileName: fileName)

        guard pem.contains("BEGIN PRIVATE KEY") || pem.contains("BEGIN EC PRIVATE KEY") else {
            throw CredentialError.notAPrivateKey(fileName: fileName)
        }
        _ = try JWTSigner(key: APIKey(id: named ?? "unknown", kind: .individual, privateKeyPEM: pem))

        return PickedKey(fileName: fileName, keyID: named, pem: pem)
    }

    /// Writes the key under the name Apple's tools look for, readable by the
    /// owner only, and answers where it went.
    ///
    /// A key kept under the wrong id signs a token whose kid names one key and
    /// whose signature comes from another. App Store Connect refuses that on
    /// every request and says only NOT_AUTHORIZED. The file name is the only
    /// thing that tells the two keys apart before a request goes out.
    @discardableResult
    public static func install(_ picked: PickedKey, keyID: String, into directory: URL) throws -> URL {
        if let named = picked.keyID, named != keyID {
            throw CredentialError.wrongKey(fileName: picked.fileName, expected: keyID, found: named)
        }

        let fileManager = FileManager.default
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: 0o700]
        )

        let url = directory.appending(path: fileName(for: keyID))
        let ownerOnly: [FileAttributeKey: Any] = [.posixPermissions: 0o600]
        // Created with the permissions already set, so the key is never on
        // disk where another account can read it, not even for a moment.
        guard fileManager.createFile(atPath: url.path, contents: Data(picked.pem.utf8), attributes: ownerOnly) else {
            throw PrivateKeyError.unwritable(url: url)
        }
        // A file that was already there keeps its old permissions otherwise.
        try fileManager.setAttributes(ownerOnly, ofItemAtPath: url.path)
        return url
    }

    /// A key readable by everyone on the machine is worth mentioning once.
    public static func isReadableByOthers(url: URL) -> Bool {
        guard
            let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
            let permissions = attributes[.posixPermissions] as? NSNumber
        else {
            return false
        }
        return permissions.intValue & 0o077 != 0
    }
}

public enum PrivateKeyError: Error, CustomLocalizedStringResourceConvertible {
    case notFound(keyID: String, looked: [URL])
    case unreadable(url: URL, underlying: any Error)
    case unwritable(url: URL)

    public var localizedStringResource: LocalizedStringResource {
        switch self {
        case let .notFound(keyID, looked):
            let places = looked.map { "  \($0.path)" }.joined(separator: "\n")
            let directory = PrivateKeyStore.recommendedDirectory.path
            let fileName = PrivateKeyStore.fileName(for: keyID)
            return LocalizedStringResource("""
            No private key for \(keyID). Looked in:
            \(places)

            Make a key in App Store Connect, under Users and Access, Integrations, \
            with the App Manager role. Then:

              mkdir -p \(directory)
              mv ~/Downloads/\(fileName) \(directory)/
              chmod 600 \(directory)/\(fileName)

            Or point \(PrivateKeyStore.environmentVariable) at the file.
            """, bundle: .here)
        case let .unreadable(url, underlying):
            return LocalizedStringResource(
                "Could not read \(url.path): \(underlying.localizedDescription)", bundle: .here
            )
        case let .unwritable(url):
            return LocalizedStringResource("Could not write \(url.path).", bundle: .here)
        }
    }
}

extension PrivateKeyError: CustomStringConvertible {
    public var description: String { String(localized: localizedStringResource) }
}
