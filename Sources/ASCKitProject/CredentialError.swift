import Foundation

/// A picked file that is not the key the project needs.
public enum CredentialError: Error, Equatable, CustomLocalizedStringResourceConvertible {
    case notAPrivateKey(fileName: String)
    case wrongKey(fileName: String, expected: String, found: String)

    public var localizedStringResource: LocalizedStringResource {
        switch self {
        case let .notAPrivateKey(fileName):
            LocalizedStringResource("""
            \(fileName) does not look like a private key. Apple's file is named \
            AuthKey_<KEY_ID>.p8 and starts with BEGIN PRIVATE KEY.
            """, bundle: .here)
        case let .wrongKey(fileName, expected, found):
            LocalizedStringResource("""
            \(fileName) holds the key \(found). This project uses \(expected). \
            Choose \(PrivateKeyStore.fileName(for: expected)), or change the Key ID in \
            the project settings.
            """, bundle: .here)
        }
    }
}

extension CredentialError: CustomStringConvertible {
    public var description: String { String(localized: localizedStringResource) }
}
