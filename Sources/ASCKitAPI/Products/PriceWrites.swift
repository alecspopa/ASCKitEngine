import Foundation

/// Which of a subscription's two prices a row is.
///
/// A yearly subscription sold with instalments has both in every country:
/// what it costs bought outright, and what one month costs. Everything else
/// has only the first.
public enum PlanType: String, Sendable, Hashable, Codable {
    case upfront = "UPFRONT"
    /// One instalment of a yearly subscription paid monthly.
    case monthly = "MONTHLY"
}

/// One country's price, as a write would send it.
public struct PriceWrite: Sendable, Hashable {
    public let territory: String
    public let pricePointID: String

    /// A yearly subscription sold with a 12-month commitment has both plan
    /// types in every country that offers it, and they have to go out
    /// together: Apple will not take twelve instalments coming to more than
    /// one and a half times the year, nor to less than the year itself.
    public let planType: PlanType

    /// `2026-09-01`, or nil to start as soon as the write lands.
    public let startDate: String?

    public init(
        territory: String,
        pricePointID: String,
        planType: PlanType = .upfront,
        startDate: String? = nil
    ) {
        self.territory = territory
        self.pricePointID = pricePointID
        self.planType = planType
        self.startDate = startDate
    }
}

// MARK: - The bodies a price write sends

extension ASCClient {
    /// The prices of one write, which do not exist yet.
    ///
    /// Each one travels in `included` under a local id, and the main resource
    /// points at those ids. A local id is unique within the one request and
    /// never comes back.
    private static func includedPrices(
        _ prices: [PriceWrite],
        resourceType: String,
        pricePoint: (relationship: String, type: String),
        owner: (relationship: String, identifier: Identifier),
        localID: (PriceWrite) -> String,
        attributes: (PriceWrite) -> [String: JSONValue]
    ) -> (identifiers: [Identifier], included: [IncludedResource]) {
        let ordered = prices.sorted {
            ($0.territory, $0.planType.rawValue) < ($1.territory, $1.planType.rawValue)
        }
        let identifiers = ordered.map { Identifier(type: resourceType, id: localID($0)) }
        let included = ordered.map { price in
            IncludedResource(
                type: resourceType,
                id: localID(price),
                attributes: attributes(price),
                relationships: [
                    owner.relationship: .one(owner.identifier),
                    pricePoint.relationship: .one(Identifier(type: pricePoint.type, id: price.pricePointID)),
                    "territory": .one(Identifier(type: "territories", id: price.territory))
                ]
            )
        }
        return (identifiers, included)
    }

    /// `null` says "from now", which is different from no start date given.
    private static func startDate(of price: PriceWrite) -> JSONValue {
        price.startDate.map(JSONValue.string) ?? .null
    }

    /// The body a price schedule write would send.
    ///
    /// Built here and nowhere else, so what a dry run prints is exactly what a
    /// real run sends. Two builders would eventually disagree, and the one
    /// somebody read would be the wrong one.
    ///
    /// A one-time purchase has one price for each country, so its local id
    /// names only the country, such as `${price-USA}`.
    ///
    /// `baseTerritory` is required, and Apple's own worked example leaves it
    /// out.
    static func priceScheduleBody(
        purchaseID: String,
        baseTerritory: String,
        prices: [PriceWrite]
    ) -> CompoundWriteRequest<NoAttributes> {
        let purchase = Identifier(type: "inAppPurchases", id: purchaseID)
        let written = includedPrices(
            prices,
            resourceType: "inAppPurchasePrices",
            pricePoint: ("inAppPurchasePricePoint", "inAppPurchasePricePoints"),
            owner: ("inAppPurchaseV2", purchase),
            localID: { "${price-\($0.territory)}" },
            attributes: { ["startDate": startDate(of: $0)] }
        )

        return CompoundWriteRequest<NoAttributes>(
            data: .init(
                type: "inAppPurchasePriceSchedules",
                id: nil,
                attributes: nil,
                relationships: [
                    "inAppPurchase": .one(purchase),
                    "baseTerritory": .one(Identifier(type: "territories", id: baseTerritory)),
                    "manualPrices": .many(written.identifiers)
                ]
            ),
            included: written.included
        )
    }

    struct SubscriptionPriceWrite: Encodable, Sendable {
        var startDate: String?
        var preserveCurrentPrice: Bool?

        /// Said out loud rather than left to a default. A yearly subscription
        /// has two prices, what it costs bought outright and what one monthly
        /// instalment costs, and this is the first one.
        var planType: String?
    }

    /// The body one country's subscription price would send.
    ///
    /// Same rule as the schedule body: one builder, so a dry run cannot print
    /// something a real run would not send.
    static func subscriptionPriceBody(
        subscriptionID: String,
        price: PriceWrite,
        preserveCurrentPrice: Bool
    ) -> WriteRequest<SubscriptionPriceWrite> {
        .create(
            "subscriptionPrices",
            attributes: SubscriptionPriceWrite(
                startDate: price.startDate,
                preserveCurrentPrice: preserveCurrentPrice,
                planType: price.planType.rawValue
            ),
            relationships: [
                "subscription": RelationshipToOne(type: "subscriptions", id: subscriptionID),
                "subscriptionPricePoint": RelationshipToOne(type: "subscriptionPricePoints", id: price.pricePointID),
                "territory": RelationshipToOne(type: "territories", id: price.territory)
            ]
        )
    }

    /// The body a whole subscription's prices would go out in.
    ///
    /// A subscription has no price schedule, but it does take a compound update
    /// the same way a one-time purchase's schedule does. One request for every
    /// country. A country can send two prices, so the local id names the plan
    /// type too, such as `${price-USA-UPFRONT}`.
    ///
    /// **Send every country you want priced, not only the ones that change.**
    /// Apple documents this update but does not say whether it replaces the
    /// price set or adds to it. Sending all of them is correct either way, and
    /// sending only the changes would wipe the rest if it replaces.
    static func subscriptionPricesBody(
        subscriptionID: String,
        prices: [PriceWrite],
        preserveCurrentPrice: Bool
    ) -> CompoundWriteRequest<NoAttributes> {
        let written = includedPrices(
            prices,
            resourceType: "subscriptionPrices",
            pricePoint: ("subscriptionPricePoint", "subscriptionPricePoints"),
            owner: ("subscription", Identifier(type: "subscriptions", id: subscriptionID)),
            localID: { "${price-\($0.territory)-\($0.planType.rawValue)}" },
            attributes: {
                [
                    "planType": .string($0.planType.rawValue),
                    "preserveCurrentPrice": .bool(preserveCurrentPrice),
                    "startDate": startDate(of: $0)
                ]
            }
        )

        return CompoundWriteRequest<NoAttributes>(
            data: .init(
                type: "subscriptions",
                id: subscriptionID,
                attributes: nil,
                relationships: ["prices": .many(written.identifiers)]
            ),
            included: written.included
        )
    }
}

// MARK: - Writing

public extension ASCClient {
    /// Replaces a one-time purchase's whole price schedule.
    ///
    /// Whole. A country left out of `prices` does not keep what it had: it goes
    /// back to Apple's equalized price from the base territory. So a caller
    /// sends every country it wants priced, every time.
    func createPriceSchedule(
        purchaseID: String,
        baseTerritory: String,
        prices: [PriceWrite]
    ) async throws {
        _ = try await post(
            "/v1/inAppPurchasePriceSchedules",
            compound: Self.priceScheduleBody(
                purchaseID: purchaseID,
                baseTerritory: baseTerritory,
                prices: prices
            ),
            as: NoAttributes.self
        )
    }

    /// Sets a subscription's price in every country at once.
    ///
    /// One request rather than one per country. Apple publishes no cap on how
    /// many the `included` array may hold and no worked example of this, so a
    /// caller that is refused should fall back to writing them one at a time,
    /// which also says which country the store objected to.
    func updateSubscriptionPrices(
        subscriptionID: String,
        prices: [PriceWrite],
        preserveCurrentPrice: Bool
    ) async throws {
        _ = try await patch(
            "/v1/subscriptions/\(subscriptionID)",
            compound: Self.subscriptionPricesBody(
                subscriptionID: subscriptionID,
                prices: prices,
                preserveCurrentPrice: preserveCurrentPrice
            ),
            as: NoAttributes.self
        )
    }

    /// Sets one country's subscription price.
    ///
    /// One country. A subscription has no price schedule, so there is nothing
    /// to replace and a country nobody writes keeps what it has.
    ///
    /// `preserveCurrentPrice` false on a rise puts every existing subscriber
    /// into Apple's consent flow. They are emailed, they have to agree, and the
    /// ones who do not answer are cancelled at renewal.
    func createSubscriptionPrice(
        subscriptionID: String,
        price: PriceWrite,
        preserveCurrentPrice: Bool
    ) async throws {
        _ = try await create(
            Self.subscriptionPriceBody(
                subscriptionID: subscriptionID,
                price: price,
                preserveCurrentPrice: preserveCurrentPrice
            ),
            as: NoAttributes.self
        )
    }
}

/// What a price write would send, as text somebody can read before it goes.
///
/// These call the same builders the real writes call. A separate builder for
/// showing and another for sending would drift apart, and the one somebody read
/// would be the wrong one.
public enum PriceWritePreview {
    public static func priceSchedule(
        purchaseID: String,
        baseTerritory: String,
        prices: [PriceWrite]
    ) -> String {
        WritePreviewJSON.text(for: ASCClient.priceScheduleBody(
            purchaseID: purchaseID,
            baseTerritory: baseTerritory,
            prices: prices
        ))
    }

    public static func subscriptionPrices(
        subscriptionID: String,
        prices: [PriceWrite],
        preserveCurrentPrice: Bool
    ) -> String {
        WritePreviewJSON.text(for: ASCClient.subscriptionPricesBody(
            subscriptionID: subscriptionID,
            prices: prices,
            preserveCurrentPrice: preserveCurrentPrice
        ))
    }

    public static func subscriptionPrice(
        subscriptionID: String,
        price: PriceWrite,
        preserveCurrentPrice: Bool
    ) -> String {
        WritePreviewJSON.text(for: ASCClient.subscriptionPriceBody(
            subscriptionID: subscriptionID,
            price: price,
            preserveCurrentPrice: preserveCurrentPrice
        ))
    }
}
