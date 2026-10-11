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
struct ProductVersionAttributes: Decodable, Sendable {
    public let state: ProductVersionState?

    /// Apple's own counter, 1 for the first.
    ///
    /// Higher is newer, which is how the words a product sells under today are
    /// found when there is no draft.
    public let version: Int?
}

/// The words of one language, as any of the three kinds holds them.
///
/// A purchase and a subscription carry a name and a description. A group
/// carries a name and a custom app name. The field a kind does not have
/// decodes to nil.
///
/// The name is 30 characters and the description is 45. Both are needed in
/// every language a product ships in: unlike a listing field, leaving one out
/// is not "leave it alone", it is a product that cannot be submitted.
struct ProductWordsAttributes: Decodable, Sendable {
    public let locale: String?
    public let name: String?
    public let description: String?
    public let customAppName: String?
    public let state: ProductLocalizationState?
}

/// The words a write sends. A field left nil is not sent, and stays as it is.
public struct WordsWrite: Encodable, Sendable {
    public var locale: String?
    public var name: String?
    public var description: String?
    public var customAppName: String?

    public init(locale: String? = nil, name: String? = nil, description: String? = nil, customAppName: String? = nil) {
        self.locale = locale
        self.name = name
        self.description = description
        self.customAppName = customAppName
    }
}

/// The three kinds of product that hold their words in a version.
///
/// They differ only in what Apple calls the resources and the paths to them.
public enum WordsOwner: Sendable {
    case inAppPurchase
    case subscription
    case subscriptionGroup

    public init(_ product: RemoteProduct) {
        self = product.isAutoRenewable ? .subscription : .inAppPurchase
    }

    var versionType: String {
        switch self {
        case .inAppPurchase: "inAppPurchaseVersions"
        case .subscription: "subscriptionVersions"
        case .subscriptionGroup: "subscriptionGroupVersions"
        }
    }

    var localizationType: String {
        switch self {
        case .inAppPurchase: "inAppPurchaseLocalizations"
        case .subscription: "subscriptionLocalizations"
        case .subscriptionGroup: "subscriptionGroupLocalizations"
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

    /// A purchase lists its versions on a `/v2` path, the other two on `/v1`.
    /// That is Apple's split, and following the other one is a 404.
    func versionsPath(parentID: String) -> String {
        switch self {
        case .inAppPurchase: "/v2/\(parentType)/\(parentID)/versions"
        case .subscription, .subscriptionGroup: "/v1/\(parentType)/\(parentID)/versions"
        }
    }

    /// The words inside a version are a `/v1` path for all three, while a
    /// write of them is a `/v2` path.
    func localizationsPath(versionID: String) -> String {
        "/v1/\(versionType)/\(versionID)/localizations"
    }

    static let wordsAPIVersion = "v2"
}

// MARK: - Reading

extension ASCClient {
    /// Every version this product holds, each with its state.
    ///
    /// Every one, not only the draft: which version to read is decided here,
    /// rather than by a filter Apple documents nowhere.
    func wordsVersions(
        of owner: WordsOwner,
        parentID: String
    ) async throws -> [Resource<ProductVersionAttributes>] {
        try await list(owner.versionsPath(parentID: parentID), as: ProductVersionAttributes.self)
    }

    func words(of owner: WordsOwner, versionID: String) async throws -> [Resource<ProductWordsAttributes>] {
        try await list(owner.localizationsPath(versionID: versionID), as: ProductWordsAttributes.self)
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

// MARK: - The bodies a write sends

extension ASCClient {
    /// Built here and nowhere else, so what a dry run prints is exactly what a
    /// real run sends. Two builders would eventually disagree, and the one
    /// somebody read would be the wrong one.
    static func wordsVersionBody(of owner: WordsOwner, parentID: String) -> WriteRequest<NoAttributes> {
        .create(
            owner.versionType,
            attributes: nil,
            relationships: [owner.relationship: RelationshipToOne(type: owner.parentType, id: parentID)]
        )
    }

    /// The words hang off the draft, and the draft hangs off the product. So
    /// the relationship is called `version` and names the version, not the
    /// product itself.
    static func wordsBody(of owner: WordsOwner, versionID: String, words: WordsWrite) -> WriteRequest<WordsWrite> {
        .create(
            owner.localizationType,
            attributes: words,
            relationships: ["version": RelationshipToOne(type: owner.versionType, id: versionID)]
        )
    }

    /// A change names the row and carries only the fields that moved.
    static func wordsChange(of owner: WordsOwner, id: String, words: WordsWrite) -> WriteRequest<WordsWrite> {
        .update(owner.localizationType, id: id, attributes: words)
    }
}

// MARK: - Writing

public extension ASCClient {
    /// Makes a draft of the words, copied from the version before it.
    ///
    /// App Store Connect answers 409 when the product already holds a draft.
    internal func createWordsVersion(
        of owner: WordsOwner,
        parentID: String
    ) async throws -> Resource<ProductVersionAttributes> {
        try await create(Self.wordsVersionBody(of: owner, parentID: parentID), as: ProductVersionAttributes.self)
    }

    /// Adds a language to a draft. The draft has to exist already.
    func createWords(of owner: WordsOwner, versionID: String, _ words: WordsWrite) async throws {
        _ = try await create(
            Self.wordsBody(of: owner, versionID: versionID, words: words),
            apiVersion: WordsOwner.wordsAPIVersion,
            as: ProductWordsAttributes.self
        )
    }

    func updateWords(of owner: WordsOwner, id: String, _ words: WordsWrite) async throws {
        _ = try await update(
            Self.wordsChange(of: owner, id: id, words: words),
            apiVersion: WordsOwner.wordsAPIVersion,
            as: ProductWordsAttributes.self
        )
    }
}

/// What a write of a product's words would send, as text somebody can read
/// before it goes.
///
/// These call the same builders the real writes call, for the reason
/// `PriceWritePreview` gives.
public enum ProductWritePreview {
    public static func newWordsVersion(of owner: WordsOwner, parentID: String) -> String {
        WritePreviewJSON.text(for: ASCClient.wordsVersionBody(of: owner, parentID: parentID))
    }

    public static func words(of owner: WordsOwner, versionID: String, _ words: WordsWrite) -> String {
        WritePreviewJSON.text(for: ASCClient.wordsBody(of: owner, versionID: versionID, words: words))
    }

    public static func wordsChange(of owner: WordsOwner, id: String, _ words: WordsWrite) -> String {
        WritePreviewJSON.text(for: ASCClient.wordsChange(of: owner, id: id, words: words))
    }
}
