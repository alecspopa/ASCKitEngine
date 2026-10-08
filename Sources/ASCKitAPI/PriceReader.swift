import Foundation

/// What one product costs, and what it could cost.
public struct RemotePrices: Sendable {
    /// Every price the store will sell this product at, keyed by country.
    public let ladders: [String: [RemotePricePoint]]

    /// What App Store Connect would charge in each country for the base price.
    /// This is Apple's own equalization, which a curve multiplies.
    public let anchors: [String: String]

    /// What each country pays today for the whole thing.
    public let current: [String: String]

    /// What one monthly instalment costs today, where the product is sold that
    /// way.
    ///
    /// Empty for anything but a yearly subscription with instalments, and
    /// missing for a country that has no instalment even on one that does.
    /// A country with no instalment today must not be given one: that would
    /// switch the monthly option on somewhere it was never offered.
    public let currentMonthly: [String: String]

    public init(
        ladders: [String: [RemotePricePoint]] = [:],
        anchors: [String: String] = [:],
        current: [String: String] = [:],
        currentMonthly: [String: String] = [:]
    ) {
        self.ladders = ladders
        self.anchors = anchors
        self.current = current
        self.currentMonthly = currentMonthly
    }
}

/// What each country pays for one product right now.
///
/// Read on every read that asks for prices, and never kept on disk. This is the
/// number a plan calls "old", so a stale one reports a rise as no change, and a
/// rise is the one thing that cannot be taken back.
public struct RemoteCurrentPrices: Sendable {
    /// What the whole thing costs, keyed by country.
    public let current: [String: String]

    /// What one instalment costs, where the product is sold that way.
    public let currentMonthly: [String: String]

    public init(current: [String: String] = [:], currentMonthly: [String: String] = [:]) {
        self.current = current
        self.currentMonthly = currentMonthly
    }
}

public struct RemotePricePoint: Sendable, Hashable {
    public let id: String
    public let territory: String
    public let customerPrice: String
    public let proceeds: String?

    public init(id: String, territory: String, customerPrice: String, proceeds: String? = nil) {
        self.id = id
        self.territory = territory
        self.customerPrice = customerPrice
        self.proceeds = proceeds
    }
}

public extension ASCClient {
    /// Reads everything needed to work out one product's prices.
    ///
    /// Three things, and they have to be asked for in order: the ladder,
    /// because the base price has to be matched to a real price point before
    /// anything else; then that point's equalizations, which are the numbers a
    /// curve multiplies; then what the store charges today, so a plan can show
    /// the change rather than only the answer.
    func prices(
        for product: RemoteProduct,
        baseTerritory: String,
        baseAmount: String,
        territories: [String]
    ) async throws -> RemotePrices {
        let wanted = Set(territories).union([baseTerritory]).sorted()
        let ladder = try await ladder(for: product, territories: wanted)

        let anchors = try await anchors(
            for: product,
            baseTerritory: baseTerritory,
            baseAmount: baseAmount,
            territories: wanted,
            ladder: ladder
        )

        let today = try await currentPrices(for: product)
        return RemotePrices(
            // One ladder serves both plan types. `filter[planType]` narrows
            // nothing: the same 800 points and the same identifiers come back
            // either way, because the plan type belongs to the price rather
            // than to the point.
            ladders: Dictionary(grouping: ladder, by: \.territory),
            anchors: anchors,
            current: today.current,
            currentMonthly: today.currentMonthly
        )
    }

    /// Everything needed to work out one product's prices, minus the ladder and
    /// the anchors, for a caller that already has those.
    ///
    /// One request for a subscription, two or three for a purchase's schedule.
    /// The cheap part of a price read, which is why it is never kept on disk.
    func ladderAndAnchors(
        for product: RemoteProduct,
        baseTerritory: String,
        baseAmount: String,
        territories: [String]
    ) async throws -> (ladders: [String: [RemotePricePoint]], anchors: [String: String]) {
        let wanted = Set(territories).union([baseTerritory]).sorted()
        let ladder = try await ladder(for: product, territories: wanted)

        let anchors = try await anchors(
            for: product,
            baseTerritory: baseTerritory,
            baseAmount: baseAmount,
            territories: wanted,
            ladder: ladder
        )
        return (Dictionary(grouping: ladder, by: \.territory), anchors)
    }

    // MARK: - The ladder

    private func ladder(
        for product: RemoteProduct,
        territories: [String]
    ) async throws -> [RemotePricePoint] {
        let resources = product.isAutoRenewable
            ? try await subscriptionPricePoints(subscriptionID: product.id, territories: territories)
            : try await inAppPurchasePricePoints(purchaseID: product.id, territories: territories)
        return resources.compactMap(Self.point)
    }

    /// A price point says which country it is for only in its relationships, so
    /// one with none is unusable rather than wrong.
    private static func point(_ resource: Resource<PricePointAttributes>) -> RemotePricePoint? {
        guard let territory = resource.related("territory"),
              let customerPrice = resource.attributes?.customerPrice
        else { return nil }

        return RemotePricePoint(
            id: resource.id,
            territory: territory,
            customerPrice: customerPrice,
            proceeds: resource.attributes?.proceeds
        )
    }

    // MARK: - Apple's own equivalent prices

    /// Empty when the base price is not a price this product can be sold at,
    /// which the plan turns into a refusal naming the nearest ones.
    private func anchors(
        for product: RemoteProduct,
        baseTerritory: String,
        baseAmount: String,
        territories: [String],
        ladder: [RemotePricePoint]
    ) async throws -> [String: String] {
        let atHome = ladder.first {
            $0.territory == baseTerritory && $0.customerPrice == baseAmount
        }
        guard let atHome else { return [:] }

        let resources = product.isAutoRenewable
            ? try await subscriptionEqualizations(pricePointID: atHome.id, territories: territories)
            : try await inAppPurchaseEqualizations(
                pricePointID: atHome.id, territories: territories
            )

        // Apple answers with the equivalent in every *other* country, so the
        // base country is not in the reply. Its own anchor is the price that
        // was asked about, and without this it is the one country a curve can
        // say nothing about.
        var found = [baseTerritory: atHome.customerPrice]
        for resource in resources {
            guard let point = Self.point(resource) else { continue }
            found[point.territory] = point.customerPrice
        }
        return found
    }

    // MARK: - What each country pays today

    func currentPrices(for product: RemoteProduct) async throws -> RemoteCurrentPrices {
        guard product.isAutoRenewable else {
            return try await RemoteCurrentPrices(
                current: currentPurchasePrices(purchaseID: product.id)
            )
        }
        let both = try await currentSubscriptionPrices(subscriptionID: product.id)
        return RemoteCurrentPrices(current: both.upfront, currentMonthly: both.monthly)
    }

    /// What a subscription costs today, one country at a time.
    ///
    /// Two rows come back per country, not one. A yearly subscription can be
    /// bought outright or paid monthly, and Apple returns both as prices: an
    /// `UPFRONT` row holding the real price and a `MONTHLY` row holding the
    /// instalment. Keeping whichever arrived last reports a yearly subscription
    /// as costing a twelfth of what it costs.
    ///
    /// Both come back, because both have to be written. Apple keeps twelve
    /// instalments between the upfront price and 1.5 times it, so moving one
    /// price without the other is refused.
    ///
    /// A product with no upfront row at all keeps whatever single row it has,
    /// because a monthly subscription has no instalments to tell apart.
    private func currentSubscriptionPrices(
        subscriptionID: String
    ) async throws -> (upfront: [String: String], monthly: [String: String]) {
        let answer = try await listIncluding(
            "/v1/subscriptions/\(subscriptionID)/prices",
            query: [
                URLQueryItem(name: "include", value: "subscriptionPricePoint,territory"),
                URLQueryItem(name: "limit", value: "200")
            ],
            as: PricePointAttributes.self
        )

        let upfront = answer.data.filter { $0.attributes?.planType == Self.upfront }
        let monthly = answer.data.filter { $0.attributes?.planType == Self.monthly }

        return (
            Self.match(
                prices: upfront.isEmpty ? answer.data : upfront,
                toPointsIn: answer.included
            ),
            Self.match(prices: monthly, toPointsIn: answer.included)
        )
    }

    /// Apple's words for the price you pay in one go, and for one instalment
    /// of it.
    private static let upfront = "UPFRONT"
    private static let monthly = "MONTHLY"

    /// A one-time purchase keeps its prices on a schedule, and the schedule
    /// keeps two lists: the countries somebody set, and the ones Apple worked
    /// out from the base territory. Both are what a buyer pays, so both count.
    private func currentPurchasePrices(purchaseID: String) async throws -> [String: String] {
        let schedule = try? await get(
            "/v2/inAppPurchases/\(purchaseID)/iapPriceSchedule",
            as: NoAttributes.self
        )
        guard let scheduleID = schedule?.id else { return [:] }

        async let manual = listIncluding(
            "/v1/inAppPurchasePriceSchedules/\(scheduleID)/manualPrices",
            query: Self.priceQuery,
            as: PricePointAttributes.self
        )
        async let automatic = listIncluding(
            "/v1/inAppPurchasePriceSchedules/\(scheduleID)/automaticPrices",
            query: Self.priceQuery,
            as: PricePointAttributes.self
        )

        // Apple's own prices first, then the ones somebody set on top.
        var found = try await Self.match(
            prices: automatic.data, toPointsIn: automatic.included
        )
        for (territory, price) in try await Self.match(
            prices: manual.data, toPointsIn: manual.included
        ) {
            found[territory] = price
        }
        return found
    }

    private static let priceQuery = [
        URLQueryItem(name: "include", value: "inAppPurchasePricePoint,territory"),
        URLQueryItem(name: "limit", value: "200")
    ]

    /// A price says what it costs only through the price point it points at, so
    /// the two have to be put back together.
    private static func match(
        prices: [Resource<PricePointAttributes>],
        toPointsIn included: [Resource<PricePointAttributes>]
    ) -> [String: String] {
        var amounts: [String: String] = [:]
        for resource in included {
            guard let amount = resource.attributes?.customerPrice else { continue }
            amounts[resource.id] = amount
        }

        var found: [String: String] = [:]
        for price in prices {
            guard let territory = price.related("territory") else { continue }
            let pointID = price.related("inAppPurchasePricePoint")
                ?? price.related("subscriptionPricePoint")
            guard let pointID, let amount = amounts[pointID] else { continue }
            found[territory] = amount
        }
        return found
    }
}
