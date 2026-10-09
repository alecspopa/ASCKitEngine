import ASCKitAPI
import Foundation

// MARK: - Where a device class goes in the library

public extension DeviceClass {
    /// The App Asset Library group that holds this device class's pictures.
    ///
    /// Computed, because `DeviceClass` is `Codable` and a stored field would
    /// change what an old project file decodes. The ids come from the
    /// reference data that App Store Connect sent for a real app.
    var placementGroup: String {
        Self.placementGroups[id] ?? "\(id.uppercased())_PROFILE"
    }

    /// Where a screenshot of this device class goes. An iMessage app has a
    /// type of its own in the same groups as the iPhone and iPad.
    var screenshotPlacementType: PlacementType {
        heading == DeviceClass.iMessageHeading ? .iMessageAppScreenshot : .appScreenshot
    }

    /// App Store Connect takes no app preview for a watch or an iMessage app.
    var takesPreviews: Bool {
        family != "Apple Watch" && screenshotPlacementType == .appScreenshot
    }

    /// The same table for every app. App Store Connect may add groups, and the
    /// reference data says which ones it knows.
    private static let placementGroups: [String: String] = [
        "iphone-6.9": "IPHONE_DYNAMIC_ISLAND_LARGE_PROFILE",
        "iphone-6.5": "IPHONE_FACE_ID_LARGE_PROFILE",
        "iphone-6.1": "IPHONE_DYNAMIC_ISLAND_MEDIUM_PROFILE",
        "iphone-duo": "IPHONE_DUO_PROFILE",
        "ipad-13": "IPAD_13_PROFILE",
        "ipad-11": "IPAD_11_PROFILE",
        "mac": "MAC_PROFILE",
        "appletv": "TV_PROFILE",
        "visionpro": "VISION_PRO_PROFILE",
        "watch-ultra": "WATCH_ULTRA_PROFILE",
        "watch-series-10": "WATCH_SERIES_10_PROFILE",
        "watch-series-7": "WATCH_SERIES_7_PROFILE",
        "watch-series-4": "WATCH_SERIES_4_PROFILE",
        "watch-series-3": "WATCH_SERIES_3_PROFILE",
        "imessage-iphone-6.9": "IMESSAGE_IPHONE_DYNAMIC_ISLAND_LARGE_PROFILE",
        "imessage-iphone-6.5": "IMESSAGE_IPHONE_FACE_ID_LARGE_PROFILE",
        "imessage-iphone-6.1": "IMESSAGE_IPHONE_DYNAMIC_ISLAND_MEDIUM_PROFILE",
        "imessage-ipad-13": "IMESSAGE_IPAD_13_PROFILE",
        "imessage-ipad-11": "IMESSAGE_IPAD_11_PROFILE"
    ]
}
