import ASCKitAPI
import Foundation

/// What a push of the images reports: the slots it wrote, the ones that
/// failed and why, and each step as it happens. `LibraryPusher` does the work.
public enum ScreenshotPusher {
    public struct Result: Sendable {
        public var uploaded: [String] = []
        public var failed: [Failure] = []

        /// The ids each written slot holds afterwards, in its order.
        public var slots: [SlotWritten] = []

        /// The approved assets that came off a slot and were archived, because
        /// nothing places them any more.
        public var archived: [RemoteLibraryAsset] = []

        public var isCompleteSuccess: Bool { failed.isEmpty }
    }

    /// One slot after a push: the assets it shows and the placements that
    /// show them, in order, and what came off it.
    public struct SlotWritten: Sendable, Hashable {
        public let slot: String
        public let assetIDs: [String]
        public let placementIDs: [String]
        public let removedPlacementIDs: [String]

        /// The assets this push uploaded for the slot. The others were in the
        /// library already.
        public let uploadedAssetIDs: [String]

        public init(
            slot: String,
            assetIDs: [String],
            placementIDs: [String],
            removedPlacementIDs: [String],
            uploadedAssetIDs: [String]
        ) {
            self.slot = slot
            self.assetIDs = assetIDs
            self.placementIDs = placementIDs
            self.removedPlacementIDs = removedPlacementIDs
            self.uploadedAssetIDs = uploadedAssetIDs
        }
    }

    public struct Failure: Sendable {
        public let locale: String
        public let deviceClassID: String
        public let message: String
    }

    public enum Step: Sendable {
        case removing(locale: String, deviceClass: String, count: Int)
        case uploading(locale: String, deviceClass: String, fileName: String)
        case placing(locale: String, deviceClass: String, count: Int)
        case ordering(locale: String, deviceClass: String)

        /// One line about the step, for whoever is watching it.
        ///
        /// Here rather than in the window and in the command line tool, which
        /// both say this and would otherwise say it differently.
        public var label: String {
            switch self {
            case let .removing(locale, deviceClass, count):
                String(localized: "\(locale) \(deviceClass): removing \(count) images", bundle: .module)
            case let .uploading(locale, deviceClass, fileName):
                String(localized: "\(locale) \(deviceClass): uploading \(fileName)", bundle: .module)
            case let .placing(locale, deviceClass, count):
                String(localized: "\(locale) \(deviceClass): placing \(count) images", bundle: .module)
            case let .ordering(locale, deviceClass):
                String(localized: "\(locale) \(deviceClass): setting the order", bundle: .module)
            }
        }
    }
}

public enum ScreenshotPushError: Error, CustomLocalizedStringResourceConvertible {
    case noLanguageOnAppStoreConnect(locale: String)

    public var localizedStringResource: LocalizedStringResource {
        switch self {
        case let .noLanguageOnAppStoreConnect(locale):
            LocalizedStringResource("""
            App Store Connect has no \(locale) page, and ASCKit never makes one. \
            Add \(locale) in App Store Connect and read again, or ignore it in this project.
            """, bundle: .here)
        }
    }
}

extension ScreenshotPushError: CustomStringConvertible {
    public var description: String { String(localized: localizedStringResource) }
}
