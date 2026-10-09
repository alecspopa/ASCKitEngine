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
        heading == "iMessage App" ? .iMessageAppScreenshot : .appScreenshot
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

    /// The foldable iPhone. It has two screens, so its group takes the sizes
    /// of both.
    ///
    /// It has no screenshot set type, so it goes up only through the library.
    /// The display type here is a stand-in that App Store Connect refuses.
    static let iPhoneDuo = DeviceClass(
        id: "iphone-duo",
        family: "iPhone",
        size: .model("Duo"),
        displayType: ScreenshotDisplayType(rawValue: "APP_IPHONE_DUO"),
        acceptedSizes: [PixelSize(1398, 2034), PixelSize(2007, 2853)]
    )
}

// MARK: - The cached reference data

/// The last reference data App Store Connect sent, kept in the project's
/// cache so that a check without a network connection uses Apple's own sizes.
public enum RefDataCache {
    public static func url(in project: Project) -> URL {
        project.cacheURL.appending(path: "asset-library-refdata.json")
    }

    /// Nil when nothing has read it yet, or when the file is damaged. Either
    /// way the built-in sizes apply.
    public static func load(in project: Project) -> AssetLibraryRefData? {
        guard let data = try? Data(contentsOf: url(in: project)) else { return nil }
        return try? JSONDecoder().decode(AssetLibraryRefData.self, from: data)
    }

    public static func save(_ refData: AssetLibraryRefData, in project: Project) throws {
        let url = url(in: project)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try ProjectJSON.write(refData, to: url, atomic: true)
    }
}

// MARK: - What a group accepts

/// The image rules of one group, from the reference data when there is some
/// and from the built-in table when there is none.
public struct ImageRules: Sendable, Equatable {
    public let sizes: [AssetLibraryRefData.Dimensions]
    public let alphaAllowed: Bool
    public let maxFileSize: Int?

    /// Lower case, with the dot, such as `.png`. Empty means any.
    public let fileExtensions: [String]

    public init(
        sizes: [AssetLibraryRefData.Dimensions],
        alphaAllowed: Bool = false,
        maxFileSize: Int? = nil,
        fileExtensions: [String] = []
    ) {
        self.sizes = sizes
        self.alphaAllowed = alphaAllowed
        self.maxFileSize = maxFileSize
        self.fileExtensions = fileExtensions
    }

    public static func screenshot(of deviceClass: DeviceClass, refData: AssetLibraryRefData?) -> ImageRules {
        let specs = refData?.imageSpecs(type: deviceClass.screenshotPlacementType, group: deviceClass.placementGroup) ?? []
        guard specs.isEmpty == false else { return builtIn(deviceClass) }

        return ImageRules(
            sizes: specs.compactMap(\.dimensions),
            alphaAllowed: specs.contains { $0.alphaAllowed == true },
            maxFileSize: specs.compactMap(\.maxFileSize).max(),
            fileExtensions: Array(Set(specs.flatMap { $0.fileExtensions ?? [] }.map { $0.lowercased() })).sorted()
        )
    }

    static func builtIn(_ deviceClass: DeviceClass) -> ImageRules {
        ImageRules(sizes: deviceClass.acceptedSizes.map {
            AssetLibraryRefData.Dimensions(
                minWidth: $0.width, maxWidth: $0.width, minHeight: $0.height, maxHeight: $0.height
            )
        })
    }

    public func accepts(width: Int, height: Int) -> Bool {
        sizes.contains { $0.fits(width: width, height: height) }
    }

    public func accepts(fileName: String) -> Bool {
        guard fileExtensions.isEmpty == false else { return true }
        let ext = "." + (fileName.split(separator: ".").last.map { $0.lowercased() } ?? "")
        return fileExtensions.contains(ext)
    }

    /// Such as `1290x2796 and 1320x2868`. A range reads as `1920x1280 to 3840x2560`.
    public var sizeList: String {
        sizes.map { size in
            let low = "\(size.minWidth)x\(size.minHeight)"
            let high = "\(size.maxWidth)x\(size.maxHeight)"
            return low == high ? low : "\(low) to \(high)"
        }
        .formatted(.list(type: .and, width: .narrow))
    }
}

// MARK: - iPhone Duo

extension Validator {
    /// From April 2027, App Store Connect takes no submission of an iPhone app
    /// without iPhone Duo screenshots. A warning until then, so a project has
    /// time to make them, and it can be silenced.
    func validateIPhoneDuo() -> [Problem] {
        let listed = config.resolvedDeviceClasses
        let shipsIPhone = listed.contains { $0.family == "iPhone" && $0.screenshotPlacementType == .appScreenshot }
        guard shipsIPhone, listed.contains(.iPhoneDuo) == false else { return [] }

        return [Problem(
            severity: .warning,
            area: .configuration,
            message: LocalizedStringResource(
                "App Store Connect needs iPhone Duo screenshots for every submission from April 2027.",
                bundle: .here
            ),
            fix: LocalizedStringResource(
                "Add \(DeviceClass.iPhoneDuo.id) to the device classes, then add its screenshots.",
                bundle: .here
            ),
            deviceClassID: DeviceClass.iPhoneDuo.id,
            path: Project.defaultConfigName,
            kind: .iPhoneDuoMissing
        )]
    }
}
