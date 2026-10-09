import ASCKitAPI
import Foundation

/// The platforms a listing can be written for, named the way a configuration
/// file names them.
///
/// `platform` in `asckit.json` is the readable name, such as `macos`. App Store
/// Connect takes `MAC_OS`, and the two are the same value in different shapes.
public extension Platform {
    static let all: [Platform] = [.ios, .macOS, .tvOS, .visionOS]

    /// The name a configuration file writes for this platform.
    var id: String {
        rawValue.lowercased().replacingOccurrences(of: "_", with: "")
    }

    /// The name Apple writes in its own documentation, such as `macOS`. A
    /// brand name, so it reads the same in every language.
    var displayName: String {
        switch self {
        case .ios: "iOS"
        case .macOS: "macOS"
        case .tvOS: "tvOS"
        case .visionOS: "visionOS"
        default: rawValue
        }
    }

    /// The platform a configuration file names, or nil for a name ASCKit does
    /// not know. An unknown name is reported by the validator rather than
    /// taking the project down with it.
    static func named(_ id: String) -> Platform? {
        all.first { $0.id == id.lowercased() }
    }
}
