import Foundation

/// Which device slot a screenshot set fills.
///
/// Apple never added a value for the 6.9-inch iPhone or the 13-inch iPad. They
/// widened the pixel sizes the old identifiers accept instead, so a 1320x2868
/// image goes up under `appIPhone67`. That mapping is confirmed by working
/// tooling rather than by Apple's own documentation.
public struct ScreenshotDisplayType: RawRepresentable, Sendable, Hashable, Codable {
    public let rawValue: String
    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static let appIPhone67 = Self(rawValue: "APP_IPHONE_67")
    public static let appIPhone65 = Self(rawValue: "APP_IPHONE_65")
    public static let appIPhone61 = Self(rawValue: "APP_IPHONE_61")
    public static let appIPhone58 = Self(rawValue: "APP_IPHONE_58")
    public static let appIPhone55 = Self(rawValue: "APP_IPHONE_55")
    public static let appIPadPro3Gen129 = Self(rawValue: "APP_IPAD_PRO_3GEN_129")
    public static let appIPadPro3Gen11 = Self(rawValue: "APP_IPAD_PRO_3GEN_11")
    public static let appIPadPro129 = Self(rawValue: "APP_IPAD_PRO_129")
    public static let appDesktop = Self(rawValue: "APP_DESKTOP")
    public static let appAppleVisionPro = Self(rawValue: "APP_APPLE_VISION_PRO")
    public static let appWatchUltra = Self(rawValue: "APP_WATCH_ULTRA")
    public static let appWatchSeries10 = Self(rawValue: "APP_WATCH_SERIES_10")
    public static let appWatchSeries7 = Self(rawValue: "APP_WATCH_SERIES_7")
    public static let appWatchSeries4 = Self(rawValue: "APP_WATCH_SERIES_4")
    public static let appWatchSeries3 = Self(rawValue: "APP_WATCH_SERIES_3")
    public static let appAppleTV = Self(rawValue: "APP_APPLE_TV")

    // An iMessage app is sold inside an iOS app and has a screenshot set of
    // its own, on the same relationship, under an identifier of its own.
    public static let iMessageIPhone67 = Self(rawValue: "IMESSAGE_APP_IPHONE_67")
    public static let iMessageIPhone65 = Self(rawValue: "IMESSAGE_APP_IPHONE_65")
    public static let iMessageIPhone61 = Self(rawValue: "IMESSAGE_APP_IPHONE_61")
    public static let iMessageIPadPro3Gen129 = Self(rawValue: "IMESSAGE_APP_IPAD_PRO_3GEN_129")
    public static let iMessageIPadPro3Gen11 = Self(rawValue: "IMESSAGE_APP_IPAD_PRO_3GEN_11")
}
