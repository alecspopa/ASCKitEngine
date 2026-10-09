import Foundation

/// A one-time in-app purchase: a consumable, a non-consumable, or a
/// subscription that does not renew.
///
/// The relationship on the app is called `inAppPurchasesV2` and the resource
/// type that comes back is `inAppPurchases`. The v1 relationship still answers
/// and returns a poorer resource, so asking for the wrong one reads as a short
/// list rather than as an error.
public struct InAppPurchaseAttributes: Decodable, Sendable {
    /// The internal name, which only App Store Connect shows.
    public let name: String?

    /// The string the app asks the store for.
    public let productId: String?

    public let inAppPurchaseType: String?

    /// `MISSING_METADATA`, `READY_TO_SUBMIT`, `IN_REVIEW`, `APPROVED` and the
    /// rest. Held as a string, because Apple adds values and a new one must not
    /// stop a read.
    public let state: String?

    public let reviewNote: String?
    public let familySharable: Bool?
    public let contentHosting: Bool?
}

/// A name and a description in one language.
///
/// The name is 30 characters and the description is 45. Both are needed in
/// every language a product ships in: unlike a listing field, leaving one out
/// is not "leave it alone", it is a product that cannot be submitted.
public struct InAppPurchaseLocalizationAttributes: Decodable, Sendable {
    public let locale: String?
    public let name: String?
    public let description: String?
    public let state: ProductLocalizationState?
}

/// One price the store is willing to charge for one product in one country.
///
/// The id encodes the product as well as the country, so a point read for one
/// product is not valid on another.
public struct PricePointAttributes: Decodable, Sendable {
    public let customerPrice: String?
    public let proceeds: String?

    /// What a subscription pays out after a customer has been subscribed for a
    /// year, which Apple takes a smaller share of. Always nil on a one-time
    /// purchase, which has no second year.
    public let proceedsYear2: String?

    /// `UPFRONT` or `MONTHLY`, on a subscription's price.
    ///
    /// Two rows come back per country for a yearly subscription: what it costs
    /// bought outright, and what one monthly instalment costs. Nil on a price
    /// point, which belongs to neither.
    public let planType: String?
}

public extension ASCClient {
    // MARK: - Products

    func inAppPurchases(appID: String) async throws -> [Resource<InAppPurchaseAttributes>] {
        try await list(
            "/v1/apps/\(appID)/inAppPurchasesV2",
            query: [.maxPageSize],
            as: InAppPurchaseAttributes.self
        )
    }

    // MARK: - Versions

    /// Every version this purchase holds, each with its state.
    ///
    /// Every one, not only the draft: which version to read is decided here,
    /// rather than by a filter Apple documents nowhere.
    func inAppPurchaseVersions(
        purchaseID: String
    ) async throws -> [Resource<ProductVersionAttributes>] {
        try await list(
            "/v2/inAppPurchases/\(purchaseID)/versions",
            query: [.maxPageSize],
            as: ProductVersionAttributes.self
        )
    }

    // MARK: - Words

    /// Note the versions, plural and mixed. The list of versions is a `/v2`
    /// path and the words inside one are a `/v1` path. That is Apple's split,
    /// not a typo, and following the other one is a 404.
    func inAppPurchaseLocalizations(
        versionID: String
    ) async throws -> [Resource<InAppPurchaseLocalizationAttributes>] {
        try await list(
            "/v1/inAppPurchaseVersions/\(versionID)/localizations",
            as: InAppPurchaseLocalizationAttributes.self
        )
    }

    // MARK: - Prices

    /// Every price this product can be sold at, in the countries asked for.
    ///
    /// The territory filter is not politeness. A product's ladder runs to
    /// thousands of rows across 175 countries, and `list` follows every next
    /// link, so an unfiltered call fetches all of them.
    ///
    /// The country each point belongs to is read off the relationship rather
    /// than out of a top-level `included` array, so nothing has to be asked for
    /// twice or matched up afterwards.
    func inAppPurchasePricePoints(
        purchaseID: String,
        territories: [String]
    ) async throws -> [Resource<PricePointAttributes>] {
        try await pricePoints(
            "/v2/inAppPurchases/\(purchaseID)/pricePoints",
            territories: territories
        )
    }

    /// The point App Store Connect considers equivalent to this one in each
    /// country asked for.
    ///
    /// This is what makes a price curve possible without an exchange rate.
    /// Apple has already converted the currency and worked the tax in, so a
    /// curve multiplies a number that is right today and stays right tomorrow.
    ///
    /// Note the version. The price points themselves come from a `/v2` path and
    /// their equalizations from a `/v1` one. There is no `/v2` equalizations
    /// endpoint, so asking for one is a 404 rather than a wrong answer.
    func inAppPurchaseEqualizations(
        pricePointID: String,
        territories: [String]
    ) async throws -> [Resource<PricePointAttributes>] {
        try await pricePoints(
            "/v1/inAppPurchasePricePoints/\(pricePointID)/equalizations",
            territories: territories
        )
    }

    /// One request per batch of countries, because a filter naming all 177 of
    /// them makes a URL nothing will accept.
    ///
    /// This assumes `filter[territory]` takes a comma-separated list. Apple's
    /// reference types every filter as an array and never says what separates
    /// one, so the assumption is untested against the real API. A batch size of
    /// 1 turns the whole thing into one request per country, which is slow and
    /// certainly correct, and is what to fall back to if a batch comes back
    /// empty or refused.
    internal func pricePoints(
        _ path: String,
        territories: [String],
        batchSize: Int = 50
    ) async throws -> [Resource<PricePointAttributes>] {
        guard territories.isEmpty == false else { return [] }

        var collected: [Resource<PricePointAttributes>] = []
        for batch in territories.chunked(into: batchSize) {
            collected += try await list(
                path,
                query: [
                    URLQueryItem(name: "filter[territory]", value: batch.joined(separator: ",")),
                    // Without this the points come back with no territory
                    // relationship at all, so every one of them is unusable and
                    // the ladder reads as empty. Filtering by territory does not
                    // imply asking for it.
                    URLQueryItem(name: "include", value: "territory"),
                    .limit(8000)
                ],
                as: PricePointAttributes.self
            )
        }
        return collected
    }
}

extension [String] {
    /// Splits a list into runs of at most `size`, so a query can name a few
    /// countries at a time rather than all of them at once.
    func chunked(into size: Int) -> [[String]] {
        guard size > 0 else { return [self] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0 ..< Swift.min($0 + size, count)])
        }
    }
}
