import Foundation

// The App Asset Library names its values as strings that Apple says will grow,
// so each one is an open set of known values and never a closed enum. A value
// this build does not know still decodes.

/// Where an image or a video in the library has got to.
public struct LibraryAssetState: RawRepresentable, Sendable, Hashable, Codable {
    public let rawValue: String
    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static let awaitingUpload = Self(rawValue: "AWAITING_UPLOAD")
    public static let uploadComplete = Self(rawValue: "UPLOAD_COMPLETE")
    public static let failed = Self(rawValue: "FAILED")
    public static let complete = Self(rawValue: "COMPLETE")
    public static let prepareForSubmission = Self(rawValue: "PREPARE_FOR_SUBMISSION")
    public static let readyForReview = Self(rawValue: "READY_FOR_REVIEW")
    public static let waitingForReview = Self(rawValue: "WAITING_FOR_REVIEW")
    public static let inReview = Self(rawValue: "IN_REVIEW")
    public static let accepted = Self(rawValue: "ACCEPTED")
    public static let approved = Self(rawValue: "APPROVED")
    public static let rejected = Self(rawValue: "REJECTED")
    public static let archived = Self(rawValue: "ARCHIVED")

    /// Still on its way in. Every other state is one a placement can use or a
    /// failure.
    public var isProcessing: Bool {
        self == .awaitingUpload || self == .uploadComplete
    }

    /// Apple sends `COMPLETE` in its list of states and documents nothing
    /// about it, so it counts as processed.
    public var canBePlaced: Bool {
        isProcessing == false && self != .failed && self != .archived
    }
}

/// What kind of media an asset is filed under. It is fixed when the asset is
/// reserved and a placement type takes only some of them.
public struct LibraryAssetCategory: RawRepresentable, Sendable, Hashable, Codable {
    public let rawValue: String
    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static let screenshotsAndPreviews = Self(rawValue: "APP_SCREENSHOTS_AND_PREVIEWS")
    public static let creativeAssets = Self(rawValue: "CREATIVE_ASSETS")
}

/// Where on the App Store a placement shows its asset.
public struct PlacementType: RawRepresentable, Sendable, Hashable, Codable {
    public let rawValue: String
    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static let appScreenshot = Self(rawValue: "APP_SCREENSHOT")
    public static let iMessageAppScreenshot = Self(rawValue: "IMESSAGE_APP_SCREENSHOT")
    public static let appPreview = Self(rawValue: "APP_PREVIEW")
    public static let productPageHeader = Self(rawValue: "PRODUCT_PAGE_HEADER_ASSET")
    public static let searchResults = Self(rawValue: "APP_STORE_SEARCH_RESULTS_ASSET")
}

/// A placement follows its parent through review.
public struct PlacementState: RawRepresentable, Sendable, Hashable, Codable {
    public let rawValue: String
    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static let assetProcessing = Self(rawValue: "ASSET_PROCESSING")
    public static let failed = Self(rawValue: "FAILED")
    public static let parentPrepareForSubmission = Self(rawValue: "PARENT_PREPARE_FOR_SUBMISSION")
    public static let parentReadyForReview = Self(rawValue: "PARENT_READY_FOR_REVIEW")
    public static let parentWaitingForReview = Self(rawValue: "PARENT_WAITING_FOR_REVIEW")
    public static let parentInReview = Self(rawValue: "PARENT_IN_REVIEW")
    public static let parentApproved = Self(rawValue: "PARENT_APPROVED")
}

/// An image or a video. Each lives at its own address, with the same calls.
public enum LibraryMedia: String, Sendable, Hashable, Codable, CaseIterable {
    case image = "IMAGE"
    case video = "VIDEO"

    /// The JSON:API type and the path both use this.
    var resourceType: String {
        switch self {
        case .image: "appAssetLibraryImages"
        case .video: "appAssetLibraryVideos"
        }
    }

    /// The name of the relationship on a placement and of the list on a library.
    var relationshipName: String {
        switch self {
        case .image: "image"
        case .video: "video"
        }
    }

    var listName: String {
        switch self {
        case .image: "images"
        case .video: "videos"
        }
    }

    init?(resourceType: String) {
        guard let match = Self.allCases.first(where: { $0.resourceType == resourceType }) else { return nil }
        self = match
    }
}

/// What a placement is placed on. ASCKit writes versions and Product Page
/// Optimization treatments. A custom product page is here because App Store
/// Connect reads and orders it the same way.
public enum PlacementParent: Sendable, Hashable {
    case versionLocalization(id: String)
    case treatmentLocalization(id: String)
    case customProductPageLocalization(id: String)

    public var id: String {
        switch self {
        case let .versionLocalization(id), let .treatmentLocalization(id),
             let .customProductPageLocalization(id):
            id
        }
    }

    var relationshipName: String {
        switch self {
        case .versionLocalization: "appStoreVersionLocalization"
        case .treatmentLocalization: "appStoreVersionExperimentTreatmentLocalization"
        case .customProductPageLocalization: "appCustomProductPageLocalization"
        }
    }

    var resourceType: String {
        switch self {
        case .versionLocalization: "appStoreVersionLocalizations"
        case .treatmentLocalization: "appStoreVersionExperimentTreatmentLocalizations"
        case .customProductPageLocalization: "appCustomProductPageLocalizations"
        }
    }

    var relationship: RelationshipToOne {
        RelationshipToOne(type: resourceType, id: id)
    }
}
