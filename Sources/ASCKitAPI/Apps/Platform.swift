import Foundation

public struct Platform: RawRepresentable, Sendable, Hashable, Codable {
    public let rawValue: String
    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static let ios = Self(rawValue: "IOS")
    public static let macOS = Self(rawValue: "MAC_OS")
    public static let tvOS = Self(rawValue: "TV_OS")
    public static let visionOS = Self(rawValue: "VISION_OS")
}
