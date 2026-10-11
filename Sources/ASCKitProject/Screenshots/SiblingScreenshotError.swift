import ASCKitAPI
import Foundation

public enum SiblingScreenshotError: ReadableError {
    case sameLanguage(String)
    case notShipped(String, shipped: [String])
    case differentLanguage(from: String, to: String)
    case noSuchDeviceClass(String, listed: [String])
    case nothingToCopy(from: String, deviceClassID: String)

    public var localizedStringResource: LocalizedStringResource {
        switch self {
        case let .sameLanguage(locale):
            LocalizedStringResource("\(locale) cannot copy its own screenshots.", bundle: .here)

        case let .notShipped(locale, shipped):
            LocalizedStringResource("""
            \(locale) is not a language this project ships. It ships \
            \(shipped.joined(separator: ", ")).
            """, bundle: .here)

        case let .differentLanguage(from, to):
            LocalizedStringResource("""
            \(from) and \(to) are different languages, so the pictures say different words. \
            Screenshots are copied only between languages such as es-ES and es-MX. \
            To show another language's screenshots, put \(to) in usesSourceScreenshots.
            """, bundle: .here)

        case let .noSuchDeviceClass(identifier, listed):
            LocalizedStringResource("""
            \(identifier) is not a device class this project lists. It lists \
            \(listed.joined(separator: ", ")).
            """, bundle: .here)

        case let .nothingToCopy(from, deviceClassID):
            LocalizedStringResource("\(from) has no \(deviceClassID) screenshots to copy.", bundle: .here)
        }
    }
}
