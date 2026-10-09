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
