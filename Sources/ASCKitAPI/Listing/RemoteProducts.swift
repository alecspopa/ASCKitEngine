import Foundation

/// Every in-app purchase App Store Connect holds for one app.
///
/// A sibling of `RemoteListing` rather than part of it. A listing belongs to a
/// version and a purchase does not, so folding the two together would make
/// every reader of a listing carry a version it has no use for.
public struct RemoteProducts: Sendable {
    public let appID: String
    public let products: [RemoteProduct]

    /// What each subscription group is called, keyed by Apple's id.
    public let groupNames: [String: String]

    /// Every subscription group, with its own words when they were read.
    public let groups: [RemoteSubscriptionGroup]

    public init(
        appID: String,
        products: [RemoteProduct],
        groupNames: [String: String],
        groups: [RemoteSubscriptionGroup] = []
    ) {
        self.appID = appID
        self.products = products
        self.groupNames = groupNames
        self.groups = groups
    }

    /// Keyed by the reference name, which is what a group file is named after
    /// and what a subscription file says.
    public var groupsByName: [String: RemoteSubscriptionGroup] {
        Dictionary(groups.map { ($0.referenceName, $0) }, uniquingKeysWith: { first, _ in first })
    }

    /// Keyed by the product id the app asks the store for, which is what a file
    /// on disk is named after.
    public var byProductID: [String: RemoteProduct] {
        Dictionary(products.map { ($0.productID, $0) }, uniquingKeysWith: { first, _ in first })
    }
}

/// One purchase, as the store holds it.
/// The version of a product's words that the store holds.
///
/// One type for all three, because an in-app purchase version, a subscription
/// version and a subscription group version differ only in what Apple calls
/// them.
public struct RemoteProductVersion: Sendable, Hashable {
    /// Apple's opaque id, which a write of the words names.
    public let id: String

    /// Apple's counter, 1 for the first. What a receipt says, so that somebody
    /// can match it against App Store Connect.
    public let number: Int?

    public let state: ProductVersionState?

    /// Whether the store takes a write to the words in this version.
    ///
    /// Nil counts as no.
    public var acceptsChanges: Bool { state?.isEditable ?? false }

    /// Whether a push makes a new draft before it writes the words.
    public var needsNewDraft: Bool { state?.takesNewDraft ?? false }

    public init(id: String, number: Int? = nil, state: ProductVersionState? = nil) {
        self.id = id
        self.number = number
        self.state = state
    }
}

public struct RemoteProduct: Sendable, Identifiable {
    /// Apple's opaque id, which every other call about this product needs.
    public let id: String

    /// The string the app asks the store for.
    public let productID: String

    /// `consumable`, `non_consumable`, `non_renewing_subscription` or
    /// `auto_renewable_subscription`, as ASCKit spells them.
    public let kind: String

    public let referenceName: String?

    /// `IN_REVIEW`, `APPROVED` and the rest. Held as a string, because Apple
    /// adds values and a new one must not stop a read.
    public let state: String?

    public let reviewNote: String?
    public let familySharable: Bool?

    /// The group's name, for a subscription. Nil for everything else.
    public let subscriptionGroup: String?

    /// `ONE_MONTH` and the rest. Nil for everything but a subscription.
    public let subscriptionPeriod: String?

    /// The version the words below came out of, and the one a push writes to.
    ///
    /// Nil when the store holds no version for this product, which is a product
    /// whose words have never been drafted.
    public let version: RemoteProductVersion?

    public let localizations: [String: RemoteProductLocalization]

    public init(
        id: String,
        productID: String,
        kind: String,
        referenceName: String? = nil,
        state: String? = nil,
        reviewNote: String? = nil,
        familySharable: Bool? = nil,
        subscriptionGroup: String? = nil,
        subscriptionPeriod: String? = nil,
        version: RemoteProductVersion? = nil,
        localizations: [String: RemoteProductLocalization] = [:]
    ) {
        self.id = id
        self.productID = productID
        self.kind = kind
        self.referenceName = referenceName
        self.state = state
        self.reviewNote = reviewNote
        self.familySharable = familySharable
        self.subscriptionGroup = subscriptionGroup
        self.subscriptionPeriod = subscriptionPeriod
        self.version = version
        self.localizations = localizations
    }

    /// Whether this is an auto-renewable subscription, which decides how its
    /// price is written and whether it belongs to a group.
    public var isAutoRenewable: Bool { kind == "auto_renewable_subscription" }

    /// The same product, with the words of another version.
    public func with(
        version: RemoteProductVersion,
        words: [RemoteProductLocalization]
    ) -> RemoteProduct {
        RemoteProduct(
            id: id,
            productID: productID,
            kind: kind,
            referenceName: referenceName,
            state: state,
            reviewNote: reviewNote,
            familySharable: familySharable,
            subscriptionGroup: subscriptionGroup,
            subscriptionPeriod: subscriptionPeriod,
            version: version,
            localizations: ASCClient.byLocale(words, key: \.locale)
        )
    }
}

/// One subscription group, as the store holds it.
public struct RemoteSubscriptionGroup: Sendable, Identifiable {
    /// Apple's opaque id, which a write of the group's words needs.
    public let id: String

    public let referenceName: String

    /// The version the words below came out of, and the one a push writes to.
    public let version: RemoteProductVersion?

    public let localizations: [String: RemoteGroupLocalization]

    public init(
        id: String,
        referenceName: String,
        version: RemoteProductVersion? = nil,
        localizations: [String: RemoteGroupLocalization] = [:]
    ) {
        self.id = id
        self.referenceName = referenceName
        self.version = version
        self.localizations = localizations
    }

    /// The same group, with the words of another version.
    public func with(
        version: RemoteProductVersion,
        words: [RemoteGroupLocalization]
    ) -> RemoteSubscriptionGroup {
        RemoteSubscriptionGroup(
            id: id,
            referenceName: referenceName,
            version: version,
            localizations: ASCClient.byLocale(words, key: \.locale)
        )
    }
}

/// One language of a subscription group, as the store holds it.
public struct RemoteGroupLocalization: Sendable {
    public let id: String
    public let locale: String
    public let name: String?

    /// The name the store shows instead of the app's own name. Nil when the
    /// app's name is used.
    public let customAppName: String?

    /// Kept for a diagnostic. Whether the store takes a write is a question
    /// about the version these words live in, and `RemoteProductVersion`
    /// answers it.
    public let state: ProductLocalizationState?

    public subscript(field: String) -> String? {
        switch field {
        case "name": name
        case "customAppName": customAppName
        default: nil
        }
    }

    public init(
        id: String,
        locale: String,
        name: String? = nil,
        customAppName: String? = nil,
        state: ProductLocalizationState? = nil
    ) {
        self.id = id
        self.locale = locale
        self.name = name
        self.customAppName = customAppName
        self.state = state
    }
}

/// One language's name and description, as the store holds it.
public struct RemoteProductLocalization: Sendable {
    /// Apple's id for this localization, which an update needs.
    public let id: String

    public let locale: String
    public let name: String?
    public let description: String?
    /// Kept for a diagnostic. Whether the store takes a write is a question
    /// about the version these words live in, and `RemoteProductVersion`
    /// answers it.
    public let state: ProductLocalizationState?

    /// The two fields by the names a file uses, so a planner can walk them
    /// rather than naming each one.
    public subscript(field: String) -> String? {
        switch field {
        case "name": name
        case "description": description
        default: nil
        }
    }

    public init(
        id: String,
        locale: String,
        name: String? = nil,
        description: String? = nil,
        state: ProductLocalizationState? = nil
    ) {
        self.id = id
        self.locale = locale
        self.name = name
        self.description = description
        self.state = state
    }
}
