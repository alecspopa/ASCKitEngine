import ASCKitAPI
import Foundation

/// A device class a project can ship screenshots for.
///
/// The name in the configuration file is the readable one, such as
/// `iphone-6.9`. It maps onto Apple's identifier, which is not readable at all:
/// Apple never added a value for the 6.9-inch iPhone or the 13-inch iPad, and
/// widened the pixel sizes the old identifiers accept instead.
///
/// One device class per identifier App Store Connect takes, and no more. The
/// store holds one set of pictures per identifier, and a push matches a local
/// set to a remote one by it, so two device classes on one identifier would
/// each overwrite the other.
public struct DeviceClass: Sendable, Hashable, Identifiable, Codable {
    public let id: String

    /// The device, written the way Apple writes it, such as `iPhone`. A brand
    /// name, so it reads the same in every language.
    public let family: String

    /// How Apple names this device apart from its family.
    public let size: Size

    /// The heading this device class sits under on the screenshots page, which
    /// is the tab App Store Connect shows it under.
    ///
    /// The same as the family for most of them. An iMessage app is the one that
    /// differs: its sets are iPhone and iPad sets, and the store gathers them
    /// under a heading of their own.
    public let heading: String

    /// Which platform's listing holds this device class. A watch set and an
    /// iMessage set both belong to the iOS listing, because a watch app and an
    /// iMessage app are both sold inside an iOS app.
    public let platform: Platform

    public let displayType: ScreenshotDisplayType

    /// The pixel sizes Apple accepts, upright for a device held upright and
    /// wide for a device that is always wide. The other way round is the same
    /// pair swapped, which `accepts` handles rather than this list repeating
    /// itself.
    public let acceptedSizes: [PixelSize]

    /// How Apple names a device apart from its family: an iPhone by the inches
    /// across its screen, a Watch by the model, and a Mac by nothing at all.
    public enum Size: Sendable, Hashable, Codable {
        case inches(String)
        case model(String)
        case familyAlone
    }

    public struct PixelSize: Sendable, Hashable, Codable, CustomStringConvertible {
        public let width: Int
        public let height: Int

        public init(_ width: Int, _ height: Int) {
            self.width = width
            self.height = height
        }

        public var description: String { "\(width)x\(height)" }
        public var swapped: PixelSize { PixelSize(height, width) }
    }

    /// The heading falls back to the family, which is right for every device
    /// class but the iMessage ones.
    public init(
        id: String,
        family: String,
        size: Size,
        heading: String? = nil,
        platform: Platform = .ios,
        displayType: ScreenshotDisplayType,
        acceptedSizes: [PixelSize]
    ) {
        self.id = id
        self.family = family
        self.size = size
        self.heading = heading ?? family
        self.platform = platform
        self.displayType = displayType
        self.acceptedSizes = acceptedSizes
    }

    public func accepts(width: Int, height: Int) -> Bool {
        let size = PixelSize(width, height)
        return acceptedSizes.contains(size) || acceptedSizes.contains(size.swapped)
    }

    /// The name in the window, such as `iPhone 6.9 inch`. The family and the
    /// model stay as they are, and the word after them translates.
    public var displayName: String {
        switch size {
        case let .inches(inches):
            String(localized: "\(family) \(inches) inch", bundle: .module)
        case let .model(model):
            "\(family) \(model)"
        case .familyAlone:
            family
        }
    }

    public var acceptedSizeList: String {
        acceptedSizes.map(\.description).formatted(.list(type: .and, width: .narrow))
    }

    /// The device as a file name writes it, such as `iPhone-6.9`.
    ///
    /// The id is lower case because it names a folder. A file name says the
    /// device the way a person writes it, and it has to say it the same way
    /// every time: this token goes to App Store Connect with the image, and a
    /// later push matches on it.
    public var fileNameToken: String {
        id.split(separator: "-")
            .map { Self.writtenWords[String($0)] ?? String($0) }
            .joined(separator: "-")
    }

    /// The words an id is built from, as a person writes them. A word that is
    /// not here is written the way the id spells it, such as `6.9`.
    private static let writtenWords = [
        "iphone": "iPhone",
        "ipad": "iPad",
        "imessage": "iMessage",
        "mac": "Mac",
        "watch": "Watch",
        "series": "Series",
        "ultra": "Ultra",
        "duo": "Duo",
        "appletv": "AppleTV",
        "visionpro": "VisionPro"
    ]

    /// Width divided by height, the way the device is held. An iPhone is about
    /// 0.46, an iPad about 0.75 and a Mac about 1.6, so one thumbnail size
    /// cannot suit them all.
    public var aspectRatio: Double {
        guard let size = acceptedSizes.first, size.height > 0 else { return 0.5 }
        return Double(size.width) / Double(size.height)
    }

    /// The widest of these images, as a ratio, or this device's own ratio when
    /// there are none.
    ///
    /// Measured from the files rather than from what the device could produce.
    /// Almost every iPhone set is upright, and leaving room for a landscape
    /// image that is not there would leave most of the row empty.
    public func widestRatio(among files: [ScreenshotFile]) -> Double {
        let ratios = files.compactMap { file -> Double? in
            guard let width = file.pixelWidth, let height = file.pixelHeight, height > 0 else {
                return nil
            }
            return Double(width) / Double(height)
        }
        return ratios.max() ?? aspectRatio
    }
}

// MARK: - iPhone

public extension DeviceClass {
    /// The two iPhone sizes Apple requires today. Everything smaller is scaled
    /// from these, so most projects need only these.
    static let iPhone69 = DeviceClass(
        id: "iphone-6.9",
        family: "iPhone",
        size: .inches("6.9"),
        displayType: .appIPhone67,
        acceptedSizes: [PixelSize(1320, 2868), PixelSize(1290, 2796), PixelSize(1260, 2736)]
    )

    static let iPhone65 = DeviceClass(
        id: "iphone-6.5",
        family: "iPhone",
        size: .inches("6.5"),
        displayType: .appIPhone65,
        acceptedSizes: [PixelSize(1284, 2778), PixelSize(1242, 2688)]
    )

    /// The slot App Store Connect now labels 6.3 inch. It takes the 6.3-inch
    /// sizes and the 6.1-inch ones Apple widened it with, and it keeps the
    /// 6.1 id because that id names the folder the files are already in.
    static let iPhone61 = DeviceClass(
        id: "iphone-6.1",
        family: "iPhone",
        size: .inches("6.1"),
        displayType: .appIPhone61,
        acceptedSizes: [
            PixelSize(1206, 2622), PixelSize(1179, 2556), PixelSize(1170, 2532),
            PixelSize(1125, 2436), PixelSize(1080, 2340)
        ]
    )
}

// MARK: - iPad

public extension DeviceClass {
    static let iPad13 = DeviceClass(
        id: "ipad-13",
        family: "iPad",
        size: .inches("13"),
        displayType: .appIPadPro3Gen129,
        acceptedSizes: [PixelSize(2064, 2752), PixelSize(2048, 2732)]
    )

    static let iPad11 = DeviceClass(
        id: "ipad-11",
        family: "iPad",
        size: .inches("11"),
        displayType: .appIPadPro3Gen11,
        acceptedSizes: [
            PixelSize(1488, 2266), PixelSize(1668, 2420),
            PixelSize(1668, 2388), PixelSize(1640, 2360)
        ]
    )
}

// MARK: - Mac, Apple TV and Apple Vision Pro

public extension DeviceClass {
    /// A Mac screenshot is wide, so its sizes are listed wide. Every other
    /// device here is listed the way it is held.
    static let mac = DeviceClass(
        id: "mac",
        family: "Mac",
        size: .familyAlone,
        platform: .macOS,
        displayType: .appDesktop,
        acceptedSizes: [
            PixelSize(2880, 1800), PixelSize(2560, 1600),
            PixelSize(1440, 900), PixelSize(1280, 800)
        ]
    )

    static let appleTV = DeviceClass(
        id: "appletv",
        family: "Apple TV",
        size: .familyAlone,
        platform: .tvOS,
        displayType: .appAppleTV,
        acceptedSizes: [PixelSize(3840, 2160), PixelSize(1920, 1080)]
    )

    static let visionPro = DeviceClass(
        id: "visionpro",
        family: "Apple Vision Pro",
        size: .familyAlone,
        platform: .visionOS,
        displayType: .appAppleVisionPro,
        acceptedSizes: [PixelSize(3840, 2160)]
    )
}

// MARK: - Apple Watch

/// A watch app is sold inside an iOS app, so these belong to the iOS listing.
public extension DeviceClass {
    /// Ultra 3 and Ultra 4 take 422x514. Ultra and Ultra 2 still take 410x502.
    static let watchUltra = DeviceClass(
        id: "watch-ultra",
        family: "Apple Watch",
        size: .model("Ultra"),
        displayType: .appWatchUltra,
        acceptedSizes: [PixelSize(422, 514), PixelSize(410, 502)]
    )

    static let watchSeries10 = DeviceClass(
        id: "watch-series-10",
        family: "Apple Watch",
        size: .model("Series 10"),
        displayType: .appWatchSeries10,
        acceptedSizes: [PixelSize(416, 496)]
    )

    static let watchSeries7 = DeviceClass(
        id: "watch-series-7",
        family: "Apple Watch",
        size: .model("Series 7"),
        displayType: .appWatchSeries7,
        acceptedSizes: [PixelSize(396, 484)]
    )

    static let watchSeries4 = DeviceClass(
        id: "watch-series-4",
        family: "Apple Watch",
        size: .model("Series 4"),
        displayType: .appWatchSeries4,
        acceptedSizes: [PixelSize(368, 448)]
    )

    static let watchSeries3 = DeviceClass(
        id: "watch-series-3",
        family: "Apple Watch",
        size: .model("Series 3"),
        displayType: .appWatchSeries3,
        acceptedSizes: [PixelSize(312, 390)]
    )
}

// MARK: - iMessage app

/// An iMessage app is sold inside an iOS app and takes pictures of its own, at
/// the sizes of the device that shows them.
public extension DeviceClass {
    private static let iMessageHeading = "iMessage App"

    static let iMessageIPhone69 = DeviceClass(
        id: "imessage-iphone-6.9",
        family: "iPhone",
        size: .inches("6.9"),
        heading: iMessageHeading,
        displayType: .iMessageIPhone67,
        acceptedSizes: iPhone69.acceptedSizes
    )

    static let iMessageIPhone65 = DeviceClass(
        id: "imessage-iphone-6.5",
        family: "iPhone",
        size: .inches("6.5"),
        heading: iMessageHeading,
        displayType: .iMessageIPhone65,
        acceptedSizes: iPhone65.acceptedSizes
    )

    static let iMessageIPhone61 = DeviceClass(
        id: "imessage-iphone-6.1",
        family: "iPhone",
        size: .inches("6.1"),
        heading: iMessageHeading,
        displayType: .iMessageIPhone61,
        acceptedSizes: iPhone61.acceptedSizes
    )

    static let iMessageIPad13 = DeviceClass(
        id: "imessage-ipad-13",
        family: "iPad",
        size: .inches("13"),
        heading: iMessageHeading,
        displayType: .iMessageIPadPro3Gen129,
        acceptedSizes: iPad13.acceptedSizes
    )

    static let iMessageIPad11 = DeviceClass(
        id: "imessage-ipad-11",
        family: "iPad",
        size: .inches("11"),
        heading: iMessageHeading,
        displayType: .iMessageIPadPro3Gen11,
        acceptedSizes: iPad11.acceptedSizes
    )
}

// MARK: - The table

public extension DeviceClass {
    /// Every device class App Store Connect takes a screenshot set for, in the
    /// order the store lists them. That order is what the screenshots page
    /// reads down, so a person moving between the two reads the same page.
    static let all: [DeviceClass] = [
        .iPhone69, .iPhone65, .iPhone61, .iPhoneDuo,
        .iPad13, .iPad11,
        .mac,
        .appleTV,
        .visionPro,
        .watchUltra, .watchSeries10, .watchSeries7, .watchSeries4, .watchSeries3,
        .iMessageIPhone69, .iMessageIPhone65, .iMessageIPhone61,
        .iMessageIPad13, .iMessageIPad11
    ]

    static func named(_ id: String) -> DeviceClass? {
        all.first { $0.id == id }
    }

    /// Every device class the listing of an app on this platform can hold.
    static func all(on platform: Platform) -> [DeviceClass] {
        all.filter { $0.platform == platform }
    }

    /// The device class a new project on this platform starts with.
    ///
    /// One, and the largest, because every smaller picture of the same app is
    /// scaled from it. A project adds the rest as it makes them.
    static func first(on platform: Platform) -> DeviceClass? {
        all(on: platform).first
    }

    /// At most 10 images per set, and a set with none is not a set.
    static let maximumScreenshotsPerSet = 10
    static let minimumScreenshotsPerSet = 1
}

/// The device classes under one heading, in the order the table lists them.
///
/// App Store Connect puts a tab over each of these, and the screenshots page
/// puts a heading over each instead, so the whole page scrolls as one.
public struct DeviceClassGroup: Sendable, Hashable, Identifiable {
    public var id: String { heading }
    public let heading: String
    public let deviceClasses: [DeviceClass]
}

public extension DeviceClass {
    /// Gathers device classes under their headings, keeping the order they
    /// arrive in.
    static func grouped(_ deviceClasses: [DeviceClass]) -> [DeviceClassGroup] {
        var headings: [String] = []
        var members: [String: [DeviceClass]] = [:]

        for deviceClass in deviceClasses {
            if members[deviceClass.heading] == nil { headings.append(deviceClass.heading) }
            members[deviceClass.heading, default: []].append(deviceClass)
        }
        return headings.map { DeviceClassGroup(heading: $0, deviceClasses: members[$0] ?? []) }
    }
}
