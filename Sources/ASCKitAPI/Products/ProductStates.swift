import Foundation

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
