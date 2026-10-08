import Foundation

/// The state of an app version.
///
/// Written as a wrapper around a raw string rather than an enum, because Apple
/// adds values and a closed enum would fail to decode a listing that is
/// otherwise fine.
public struct AppVersionState: RawRepresentable, Sendable, Hashable, Codable {
    public let rawValue: String
    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static let accepted = Self(rawValue: "ACCEPTED")
    public static let developerRejected = Self(rawValue: "DEVELOPER_REJECTED")
    public static let inReview = Self(rawValue: "IN_REVIEW")
    public static let invalidBinary = Self(rawValue: "INVALID_BINARY")
    public static let metadataRejected = Self(rawValue: "METADATA_REJECTED")
    public static let pendingAppleRelease = Self(rawValue: "PENDING_APPLE_RELEASE")
    public static let pendingDeveloperRelease = Self(rawValue: "PENDING_DEVELOPER_RELEASE")
    public static let prepareForSubmission = Self(rawValue: "PREPARE_FOR_SUBMISSION")
    public static let processingForDistribution = Self(rawValue: "PROCESSING_FOR_DISTRIBUTION")
    public static let readyForDistribution = Self(rawValue: "READY_FOR_DISTRIBUTION")
    public static let readyForReview = Self(rawValue: "READY_FOR_REVIEW")
    public static let rejected = Self(rawValue: "REJECTED")
    public static let replacedWithNewVersion = Self(rawValue: "REPLACED_WITH_NEW_VERSION")
    public static let waitingForExportCompliance = Self(rawValue: "WAITING_FOR_EXPORT_COMPLIANCE")
    public static let waitingForReview = Self(rawValue: "WAITING_FOR_REVIEW")

    /// States where both text and screenshots can be changed.
    public static let fullyEditable: Set<Self> = [
        .prepareForSubmission, .developerRejected, .rejected, .metadataRejected, .invalidBinary
    ]

    /// Waiting for Review takes some text edits but refuses screenshots.
    public static let textOnlyEditable: Set<Self> = [.waitingForReview]

    public var acceptsTextChanges: Bool {
        Self.fullyEditable.contains(self) || Self.textOnlyEditable.contains(self)
    }

    public var acceptsScreenshotChanges: Bool {
        Self.fullyEditable.contains(self)
    }
}

/// The state of the app-level information, which is what gates the name and the
/// subtitle. An app returns more than one of these: one live, one editable.
public struct AppInfoState: RawRepresentable, Sendable, Hashable, Codable {
    public let rawValue: String
    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static let accepted = Self(rawValue: "ACCEPTED")
    public static let developerRejected = Self(rawValue: "DEVELOPER_REJECTED")
    public static let inReview = Self(rawValue: "IN_REVIEW")
    public static let pendingRelease = Self(rawValue: "PENDING_RELEASE")
    public static let prepareForSubmission = Self(rawValue: "PREPARE_FOR_SUBMISSION")
    public static let readyForDistribution = Self(rawValue: "READY_FOR_DISTRIBUTION")
    public static let readyForReview = Self(rawValue: "READY_FOR_REVIEW")
    public static let rejected = Self(rawValue: "REJECTED")
    public static let replacedWithNewInfo = Self(rawValue: "REPLACED_WITH_NEW_INFO")
    public static let waitingForReview = Self(rawValue: "WAITING_FOR_REVIEW")

    /// A version pulled back or rejected leaves its app information in the
    /// same state, and App Store Connect takes a new name there too.
    public static let editable: Set<Self> = [.prepareForSubmission, .developerRejected, .rejected]

    public var isEditable: Bool { Self.editable.contains(self) }
}

/// The state of one version of a product's words.
///
/// An in-app purchase, a subscription and a subscription group each hold
/// versions, and all three run through the same states, so one type covers
/// them.
///
/// A wrapper around a raw string rather than an enum, for the reason every
/// state here is: Apple adds values, and a new one must not stop a read.
public struct ProductVersionState: RawRepresentable, Sendable, Hashable, Codable {
    public let rawValue: String
    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static let accepted = Self(rawValue: "ACCEPTED")
    public static let approved = Self(rawValue: "APPROVED")
    public static let developerRejected = Self(rawValue: "DEVELOPER_REJECTED")
    public static let inReview = Self(rawValue: "IN_REVIEW")
    public static let prepareForSubmission = Self(rawValue: "PREPARE_FOR_SUBMISSION")
    public static let readyForReview = Self(rawValue: "READY_FOR_REVIEW")
    public static let rejected = Self(rawValue: "REJECTED")
    public static let replacedWithNewVersion = Self(rawValue: "REPLACED_WITH_NEW_VERSION")
    public static let waitingForReview = Self(rawValue: "WAITING_FOR_REVIEW")

    /// The one state the store takes a change in. Every other state is a
    /// version review has already seen, and Apple answers a change to one with
    /// a refusal.
    ///
    /// The web page of App Store Connect edits an approved product, but it
    /// makes a new draft first. The API answers "Version is not in modifiable
    /// state" instead.
    public var isEditable: Bool { self == .prepareForSubmission }

    /// Review is done with this version, so a new draft can follow it.
    ///
    /// Every other state is a draft, a version that review has now, or a state
    /// Apple adds later. A push refuses those.
    public var takesNewDraft: Bool {
        [.approved, .accepted, .rejected, .developerRejected].contains(self)
    }
}

/// The state of one language of an in-app purchase.
///
/// A product that has been through review holds two rows for a language it has
/// already sold in: the words on sale now, and a draft that takes changes. Both
/// come back from the same list, and a write to the live one is refused with
/// `Cannot edit InAppPurchaseLocalization when it is in ACTIVE state`.
///
/// Apple's own reference lists four values and the store answers with a fifth,
/// `ACTIVE`, on the live row. So this is a wrapper around a raw string rather
/// than an enum, and anything the reference does not name counts as locked.
public struct ProductLocalizationState: RawRepresentable, Sendable, Hashable, Codable {
    public let rawValue: String
    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static let active = Self(rawValue: "ACTIVE")
    public static let approved = Self(rawValue: "APPROVED")
    public static let prepareForSubmission = Self(rawValue: "PREPARE_FOR_SUBMISSION")
    public static let rejected = Self(rawValue: "REJECTED")
    public static let waitingForReview = Self(rawValue: "WAITING_FOR_REVIEW")

    /// The one state the store takes a change in. A rejected row is refused the
    /// same way a live one is.
    public var isEditable: Bool { self == .prepareForSubmission }
}

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

/// Where Apple has got to with an image it is ingesting.
public struct AssetDeliveryState: Sendable, Hashable, Decodable {
    public struct State: RawRepresentable, Sendable, Hashable, Codable {
        public let rawValue: String
        public init(rawValue: String) {
            self.rawValue = rawValue
        }

        public static let awaitingUpload = Self(rawValue: "AWAITING_UPLOAD")
        public static let uploadComplete = Self(rawValue: "UPLOAD_COMPLETE")
        public static let complete = Self(rawValue: "COMPLETE")
        public static let failed = Self(rawValue: "FAILED")

        public var isTerminal: Bool { self == .complete || self == .failed }
    }

    public let state: State?
    public let errors: [ASCErrorDetail]?
    public let warnings: [ASCErrorDetail]?
}
