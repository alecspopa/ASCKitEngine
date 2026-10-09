import Foundation

/// A set of subscriptions a customer picks one of.
///
/// A subscription hangs off a group rather than off the app, so reading them
/// takes two hops. Moving between the tiers of one group is an upgrade, and
/// moving between groups is not, which is why the group exists at all.
public struct SubscriptionGroupAttributes: Decodable, Sendable {
    public let referenceName: String?
}

public struct SubscriptionAttributes: Decodable, Sendable {
    /// The internal name, which only App Store Connect shows.
    public let name: String?

    public let productId: String?

    /// `ONE_WEEK`, `ONE_MONTH`, `ONE_YEAR` and the rest.
    public let subscriptionPeriod: String?

    /// The same words an in-app purchase uses, and held as a string for the
    /// same reason.
    public let state: String?

    public let reviewNote: String?
    public let familySharable: Bool?

    /// Where this tier sits in its group. 1 is the top.
    public let groupLevel: Int?
}

/// A group's own words: the name a customer reads above the tiers, and an
/// optional name that replaces the app's own name beside them.
public struct SubscriptionGroupLocalizationAttributes: Decodable, Sendable {
    public let locale: String?
    public let name: String?
    public let customAppName: String?
    public let state: ProductLocalizationState?
}

public struct SubscriptionLocalizationAttributes: Decodable, Sendable {
    public let locale: String?
    public let name: String?
    public let description: String?
    public let state: ProductLocalizationState?
}

public extension ASCClient {
    // MARK: - Products

    func subscriptionGroups(appID: String) async throws -> [Resource<SubscriptionGroupAttributes>] {
        try await list(
            "/v1/apps/\(appID)/subscriptionGroups",
            query: [.maxPageSize],
            as: SubscriptionGroupAttributes.self
        )
    }

    func subscriptions(groupID: String) async throws -> [Resource<SubscriptionAttributes>] {
        try await list(
            "/v1/subscriptionGroups/\(groupID)/subscriptions",
            query: [.maxPageSize],
            as: SubscriptionAttributes.self
        )
    }

    // MARK: - Versions

    /// Every version this subscription holds, each with its state.
    func subscriptionVersions(
        subscriptionID: String
    ) async throws -> [Resource<ProductVersionAttributes>] {
        try await list(
            "/v1/subscriptions/\(subscriptionID)/versions",
            query: [.maxPageSize],
            as: ProductVersionAttributes.self
        )
    }

    /// Every version this group holds, each with its state.
    func subscriptionGroupVersions(
        groupID: String
    ) async throws -> [Resource<ProductVersionAttributes>] {
        try await list(
            "/v1/subscriptionGroups/\(groupID)/versions",
            query: [.maxPageSize],
            as: ProductVersionAttributes.self
        )
    }

    // MARK: - Words

    func subscriptionGroupLocalizations(
        versionID: String
    ) async throws -> [Resource<SubscriptionGroupLocalizationAttributes>] {
        try await list(
            "/v1/subscriptionGroupVersions/\(versionID)/localizations",
            as: SubscriptionGroupLocalizationAttributes.self
        )
    }

    func subscriptionLocalizations(
        versionID: String
    ) async throws -> [Resource<SubscriptionLocalizationAttributes>] {
        try await list(
            "/v1/subscriptionVersions/\(versionID)/localizations",
            as: SubscriptionLocalizationAttributes.self
        )
    }

    // MARK: - Prices

    func subscriptionPricePoints(
        subscriptionID: String,
        territories: [String]
    ) async throws -> [Resource<PricePointAttributes>] {
        try await pricePoints(
            "/v1/subscriptions/\(subscriptionID)/pricePoints",
            territories: territories
        )
    }

    /// What App Store Connect would charge in each country for this price.
    /// The same idea as the one-time purchase call, on a different path.
    func subscriptionEqualizations(
        pricePointID: String,
        territories: [String]
    ) async throws -> [Resource<PricePointAttributes>] {
        try await pricePoints(
            "/v1/subscriptionPricePoints/\(pricePointID)/equalizations",
            territories: territories
        )
    }

    static let subscriptionPricesQuery = [
        URLQueryItem(name: "include", value: "subscriptionPricePoint,territory"),
        .maxPageSize
    ]

    /// What each country is charged today.
    ///
    /// A subscription has no price schedule resource. Its prices are a list,
    /// one per country, and a new one supersedes the old from its start date.
    func subscriptionPrices(
        subscriptionID: String
    ) async throws -> [Resource<SubscriptionPriceAttributes>] {
        try await list(
            "/v1/subscriptions/\(subscriptionID)/prices",
            query: ASCClient.subscriptionPricesQuery,
            as: SubscriptionPriceAttributes.self
        )
    }
}

public struct SubscriptionPriceAttributes: Decodable, Sendable {
    public let startDate: String?

    /// Whether people who already subscribe keep what they pay.
    ///
    /// The write says `preserveCurrentPrice` and the read says `preserved`.
    /// Same fact, two names, and asking for the write's name here decodes to
    /// nil every time rather than failing.
    public let preserved: Bool?

    public let planType: String?
}
