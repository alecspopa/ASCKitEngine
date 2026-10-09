import Foundation

/// A version of a product's words: the draft container App Review looks at.
///
/// An in-app purchase, a subscription and a subscription group each hold their
/// own, and all three carry the same two fields.
///
/// A version that review has seen is read-only. To change its words, a push
/// makes a new draft, which copies the words and images of the version before
/// it. The web page of App Store Connect does the same when somebody saves an
/// approved product. A draft goes to App Review only when a review submission
/// holds it, so making one sends nothing to review.
public struct ProductVersionAttributes: Decodable, Sendable {
    public let state: ProductVersionState?

    /// Apple's own counter, 1 for the first.
    ///
    /// Higher is newer, which is how the words a product sells under today are
    /// found when there is no draft.
    public let version: Int?
}

/// The three kinds of product that hold their words in a version.
///
/// They differ only in what Apple calls the version and the parent it hangs
/// off.
public enum WordsOwner: Sendable {
    case inAppPurchase
    case subscription
    case subscriptionGroup

    var versionType: String {
        switch self {
        case .inAppPurchase: "inAppPurchaseVersions"
        case .subscription: "subscriptionVersions"
        case .subscriptionGroup: "subscriptionGroupVersions"
        }
    }

    var relationship: String {
        switch self {
        case .inAppPurchase: "inAppPurchase"
        case .subscription: "subscription"
        case .subscriptionGroup: "subscriptionGroup"
        }
    }

    var parentType: String {
        switch self {
        case .inAppPurchase: "inAppPurchases"
        case .subscription: "subscriptions"
        case .subscriptionGroup: "subscriptionGroups"
        }
    }
}

extension ASCClient {
    /// The version whose words a reader should show.
    ///
    /// The draft, when the store holds one. It is what App Store Connect shows,
    /// it is what a push writes, and the live words change to match it at the
    /// next review. This is where the draft-wins rule lives now: a
    /// version-scoped read answers with one row per language, so nothing
    /// downstream has to tell a live row from a draft one.
    ///
    /// Otherwise the newest version review has already seen, which is what the
    /// store sells under today. Newest by Apple's counter rather than by state:
    /// a version in review holds newer words than the approved one, and the
    /// counter says which is which without guessing at the order of a state
    /// machine.
    ///
    /// Nil when the product holds no version, which is a product whose words
    /// have never been drafted.
    static func wordsVersion(
        in versions: [Resource<ProductVersionAttributes>]
    ) -> Resource<ProductVersionAttributes>? {
        if let draft = versions.first(where: { $0.attributes?.state?.isEditable == true }) {
            return draft
        }
        let current = versions.filter {
            $0.attributes?.state != .replacedWithNewVersion
        }
        return newest(in: current) ?? newest(in: versions)
    }

    private static func newest(
        in versions: [Resource<ProductVersionAttributes>]
    ) -> Resource<ProductVersionAttributes>? {
        versions.max { ($0.attributes?.version ?? 0) < ($1.attributes?.version ?? 0) }
    }
}

public extension ASCClient {
    // MARK: - A new draft

    /// Makes a draft of the words, copied from the version before it.
    ///
    /// App Store Connect answers 409 when the product already holds a draft.
    func createWordsVersion(
        of owner: WordsOwner,
        parentID: String
    ) async throws -> Resource<ProductVersionAttributes> {
        try await post(
            "/v1/\(owner.versionType)",
            body: Self.wordsVersionBody(of: owner, parentID: parentID),
            as: ProductVersionAttributes.self
        )
    }
}

extension ASCClient {
    /// The one builder, so a dry run shows exactly what a real run sends.
    static func wordsVersionBody(
        of owner: WordsOwner,
        parentID: String
    ) -> WriteRequest<NoAttributes> {
        WriteRequest<NoAttributes>(
            data: .init(
                type: owner.versionType,
                id: nil,
                attributes: nil,
                relationships: [
                    owner.relationship: RelationshipToOne(type: owner.parentType, id: parentID)
                ]
            )
        )
    }
}

public extension ProductWritePreview {
    static func newWordsVersion(of owner: WordsOwner, parentID: String) -> String {
        WritePreviewJSON.text(for: ASCClient.wordsVersionBody(of: owner, parentID: parentID))
    }
}
