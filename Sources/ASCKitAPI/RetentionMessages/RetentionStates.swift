import Foundation

/// The state of one version of a retention message.
///
/// A raw string wrapper, like `ProductVersionState`, so a value Apple adds
/// later does not stop a read.
public struct RetentionVersionState: RawRepresentable, Sendable, Hashable, Codable {
    public let rawValue: String
    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static let prepareForSubmission = Self(rawValue: "PREPARE_FOR_SUBMISSION")
    public static let readyForReview = Self(rawValue: "READY_FOR_REVIEW")
    public static let waitingForReview = Self(rawValue: "WAITING_FOR_REVIEW")
    public static let inReview = Self(rawValue: "IN_REVIEW")
    public static let developerRejected = Self(rawValue: "DEVELOPER_REJECTED")
    public static let rejected = Self(rawValue: "REJECTED")
    public static let accepted = Self(rawValue: "ACCEPTED")
    public static let approved = Self(rawValue: "APPROVED")

    /// The one state that takes a change. ASCKit writes no other.
    public var isEditable: Bool { self == .prepareForSubmission }

    /// How recent a version in this state is. A version has no number, so the
    /// state says which one is newer: a draft follows a version in review,
    /// which follows the approved one.
    var recency: Int {
        switch self {
        case .prepareForSubmission: 7
        case .readyForReview: 6
        case .waitingForReview: 5
        case .inReview: 4
        case .rejected, .developerRejected: 3
        case .accepted: 2
        case .approved: 1
        default: 0
        }
    }
}
