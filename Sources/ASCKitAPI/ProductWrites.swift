import Foundation

/// One country's price, as a write would send it.
public struct PriceWrite: Sendable, Hashable {
    public let territory: String
    public let pricePointID: String

    /// `UPFRONT` for the price of the year, `MONTHLY` for one instalment of it.
    ///
    /// A yearly subscription sold with a 12-month commitment has both in every
    /// country that offers it, and they have to go out together: Apple will not
    /// take twelve instalments coming to more than one and a half times the
    /// year, nor to less than the year itself.
    public let planType: String

    /// `2026-09-01`, or nil to start as soon as the write lands.
    public let startDate: String?

    public init(
        territory: String,
        pricePointID: String,
        planType: String = "UPFRONT",
        startDate: String? = nil
    ) {
        self.territory = territory
        self.pricePointID = pricePointID
        self.planType = planType
        self.startDate = startDate
    }
}

struct ProductLocalizationWrite: Encodable, Sendable {
    var locale: String?
    var name: String?
    var description: String?
}

struct GroupLocalizationWrite: Encodable, Sendable {
    var locale: String?
    var name: String?
    var customAppName: String?
}

extension ASCClient {
    // MARK: - The bodies a word write sends

    /// Built here and nowhere else, so what a dry run prints is exactly what a
    /// real run sends. Two builders would eventually disagree, and the one
    /// somebody read would be the wrong one.
    ///
    /// One builder for a purchase and a subscription, because they differ only
    /// in what Apple calls the resource and the version it hangs off.
    static func productLocalizationBody(
        type: String,
        versionType: String,
        versionID: String,
        attributes: ProductLocalizationWrite
    ) -> WriteRequest<ProductLocalizationWrite> {
        WriteRequest<ProductLocalizationWrite>(
            data: .init(
                type: type,
                id: nil,
                attributes: attributes,
                relationships: [
                    "version": RelationshipToOne(type: versionType, id: versionID)
                ]
            )
        )
    }

    /// A change names the row and carries only the fields that moved. A field
    /// left out stays as it is, which is why neither write sends nil.
    static func productLocalizationChange(
        type: String,
        id: String,
        attributes: ProductLocalizationWrite
    ) -> WriteRequest<ProductLocalizationWrite> {
        WriteRequest<ProductLocalizationWrite>(
            data: .init(type: type, id: id, attributes: attributes, relationships: nil)
        )
    }

    static func groupLocalizationChange(
        id: String,
        attributes: GroupLocalizationWrite
    ) -> WriteRequest<GroupLocalizationWrite> {
        WriteRequest<GroupLocalizationWrite>(
            data: .init(
                type: "subscriptionGroupLocalizations",
                id: id,
                attributes: attributes,
                relationships: nil
            )
        )
    }

    /// A group's words carry a custom app name where a product's carry a
    /// description, so they need a body of their own.
    static func groupLocalizationBody(
        versionID: String,
        attributes: GroupLocalizationWrite
    ) -> WriteRequest<GroupLocalizationWrite> {
        WriteRequest<GroupLocalizationWrite>(
            data: .init(
                type: "subscriptionGroupLocalizations",
                id: nil,
                attributes: attributes,
                relationships: [
                    "version": RelationshipToOne(
                        type: "subscriptionGroupVersions", id: versionID
                    )
                ]
            )
        )
    }
}

public extension ASCClient {
    // MARK: - Words

    /// The words hang off the draft, and the draft hangs off the purchase. So
    /// the relationship is called `version` and names an
    /// `inAppPurchaseVersions`, not the purchase itself.
    ///
    /// The draft has to exist already. `newWordsDraft(for:)` makes one when
    /// review is done with the version before it.
    func createInAppPurchaseLocalization(
        versionID: String,
        locale: String,
        name: String,
        description: String?
    ) async throws -> Resource<InAppPurchaseLocalizationAttributes> {
        try await post(
            "/v2/inAppPurchaseLocalizations",
            body: Self.productLocalizationBody(
                type: "inAppPurchaseLocalizations",
                versionType: "inAppPurchaseVersions",
                versionID: versionID,
                attributes: ProductLocalizationWrite(
                    locale: locale, name: name, description: description
                )
            ),
            as: InAppPurchaseLocalizationAttributes.self
        )
    }

    func updateInAppPurchaseLocalization(
        id: String,
        name: String? = nil,
        description: String? = nil
    ) async throws -> Resource<InAppPurchaseLocalizationAttributes> {
        try await patch(
            "/v2/inAppPurchaseLocalizations/\(id)",
            body: Self.productLocalizationChange(
                type: "inAppPurchaseLocalizations",
                id: id,
                attributes: ProductLocalizationWrite(name: name, description: description)
            ),
            as: InAppPurchaseLocalizationAttributes.self
        )
    }

    func createSubscriptionLocalization(
        versionID: String,
        locale: String,
        name: String,
        description: String?
    ) async throws -> Resource<SubscriptionLocalizationAttributes> {
        try await post(
            "/v2/subscriptionLocalizations",
            body: Self.productLocalizationBody(
                type: "subscriptionLocalizations",
                versionType: "subscriptionVersions",
                versionID: versionID,
                attributes: ProductLocalizationWrite(
                    locale: locale, name: name, description: description
                )
            ),
            as: SubscriptionLocalizationAttributes.self
        )
    }

    func updateSubscriptionLocalization(
        id: String,
        name: String? = nil,
        description: String? = nil
    ) async throws -> Resource<SubscriptionLocalizationAttributes> {
        try await patch(
            "/v2/subscriptionLocalizations/\(id)",
            body: Self.productLocalizationChange(
                type: "subscriptionLocalizations",
                id: id,
                attributes: ProductLocalizationWrite(name: name, description: description)
            ),
            as: SubscriptionLocalizationAttributes.self
        )
    }

    // MARK: - A subscription group's words

    func createSubscriptionGroupLocalization(
        versionID: String,
        locale: String,
        name: String,
        customAppName: String?
    ) async throws -> Resource<SubscriptionGroupLocalizationAttributes> {
        try await post(
            "/v2/subscriptionGroupLocalizations",
            body: Self.groupLocalizationBody(
                versionID: versionID,
                attributes: GroupLocalizationWrite(
                    locale: locale, name: name, customAppName: customAppName
                )
            ),
            as: SubscriptionGroupLocalizationAttributes.self
        )
    }

    func updateSubscriptionGroupLocalization(
        id: String,
        name: String? = nil,
        customAppName: String? = nil
    ) async throws -> Resource<SubscriptionGroupLocalizationAttributes> {
        try await patch(
            "/v2/subscriptionGroupLocalizations/\(id)",
            body: Self.groupLocalizationChange(
                id: id,
                attributes: GroupLocalizationWrite(name: name, customAppName: customAppName)
            ),
            as: SubscriptionGroupLocalizationAttributes.self
        )
    }

    // MARK: - A one-time purchase's prices

    /// The body a price schedule write would send.
    ///
    /// Built here and nowhere else, so what a dry run prints is exactly what a
    /// real run sends. Two builders would eventually disagree, and the one
    /// somebody read would be the wrong one.
    ///
    /// The prices do not exist yet, so each one travels in `included` under a
    /// local id such as `${price-USA}`, and `manualPrices` points at those ids.
    /// A local id is unique within this request and never comes back.
    ///
    /// `baseTerritory` is required, and Apple's own worked example leaves it
    /// out.
    internal static func priceScheduleBody(
        purchaseID: String,
        baseTerritory: String,
        prices: [PriceWrite]
    ) -> CompoundWriteRequest<NoAttributes> {
        let ordered = prices.sorted { $0.territory < $1.territory }

        let identifiers = ordered.map {
            Identifier(type: "inAppPurchasePrices", id: localID(for: $0.territory))
        }

        let included = ordered.map { price in
            IncludedResource(
                type: "inAppPurchasePrices",
                id: localID(for: price.territory),
                attributes: ["startDate": price.startDate.map(JSONValue.string) ?? .null],
                relationships: [
                    "inAppPurchaseV2": .one(Identifier(type: "inAppPurchases", id: purchaseID)),
                    "inAppPurchasePricePoint": .one(Identifier(
                        type: "inAppPurchasePricePoints", id: price.pricePointID
                    )),
                    "territory": .one(Identifier(type: "territories", id: price.territory))
                ]
            )
        }

        return CompoundWriteRequest<NoAttributes>(
            data: .init(
                type: "inAppPurchasePriceSchedules",
                id: nil,
                attributes: nil,
                relationships: [
                    "inAppPurchase": .one(Identifier(type: "inAppPurchases", id: purchaseID)),
                    "baseTerritory": .one(Identifier(type: "territories", id: baseTerritory)),
                    "manualPrices": .many(identifiers)
                ]
            ),
            included: included
        )
    }

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

    /// A local id has to be unique in the request, and a country now sends
    /// two prices rather than one.
    private static func localID(for price: PriceWrite) -> String {
        "${price-\(price.territory)-\(price.planType)}"
    }

    private static func localID(for territory: String) -> String {
        "${price-\(territory)}"
    }

    // MARK: - A subscription's prices

    internal struct SubscriptionPriceWrite: Encodable, Sendable {
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
    internal static func subscriptionPriceBody(
        subscriptionID: String,
        price: PriceWrite,
        preserveCurrentPrice: Bool
    ) -> WriteRequest<SubscriptionPriceWrite> {
        WriteRequest<SubscriptionPriceWrite>(
            data: .init(
                type: "subscriptionPrices",
                id: nil,
                attributes: SubscriptionPriceWrite(
                    startDate: price.startDate,
                    preserveCurrentPrice: preserveCurrentPrice,
                    planType: price.planType
                ),
                relationships: [
                    "subscription": RelationshipToOne(
                        type: "subscriptions", id: subscriptionID
                    ),
                    "subscriptionPricePoint": RelationshipToOne(
                        type: "subscriptionPricePoints", id: price.pricePointID
                    ),
                    "territory": RelationshipToOne(
                        type: "territories", id: price.territory
                    )
                ]
            )
        )
    }

    /// The body a whole subscription's prices would go out in.
    ///
    /// A subscription has no price schedule, but it does take a compound update
    /// the same way a one-time purchase's schedule does: the prices do not
    /// exist yet, so each one travels in `included` under a local id, and
    /// `prices` points at those ids. One request for every country.
    ///
    /// **Send every country you want priced, not only the ones that change.**
    /// Apple documents this update but does not say whether it replaces the
    /// price set or adds to it. Sending all of them is correct either way, and
    /// sending only the changes would wipe the rest if it replaces.
    internal static func subscriptionPricesBody(
        subscriptionID: String,
        prices: [PriceWrite],
        preserveCurrentPrice: Bool
    ) -> CompoundWriteRequest<NoAttributes> {
        let ordered = prices.sorted {
            ($0.territory, $0.planType) < ($1.territory, $1.planType)
        }

        let identifiers = ordered.map {
            Identifier(type: "subscriptionPrices", id: localID(for: $0))
        }

        let included = ordered.map { price in
            IncludedResource(
                type: "subscriptionPrices",
                id: localID(for: price),
                attributes: [
                    "planType": .string(price.planType),
                    "preserveCurrentPrice": .bool(preserveCurrentPrice),
                    "startDate": price.startDate.map(JSONValue.string) ?? .null
                ],
                relationships: [
                    "subscription": .one(Identifier(
                        type: "subscriptions", id: subscriptionID
                    )),
                    "subscriptionPricePoint": .one(Identifier(
                        type: "subscriptionPricePoints", id: price.pricePointID
                    )),
                    "territory": .one(Identifier(type: "territories", id: price.territory))
                ]
            )
        }

        return CompoundWriteRequest<NoAttributes>(
            data: .init(
                type: "subscriptions",
                id: subscriptionID,
                attributes: nil,
                relationships: ["prices": .many(identifiers)]
            ),
            included: included
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
        _ = try await post(
            "/v1/subscriptionPrices",
            body: Self.subscriptionPriceBody(
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
        json(ASCClient.priceScheduleBody(
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
        json(ASCClient.subscriptionPricesBody(
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
        json(ASCClient.subscriptionPriceBody(
            subscriptionID: subscriptionID,
            price: price,
            preserveCurrentPrice: preserveCurrentPrice
        ))
    }

    private static func json(_ value: some Encodable) -> String {
        WritePreviewJSON.text(for: value)
    }
}

/// What a write of a product's words would send, as text somebody can read
/// before it goes.
///
/// These call the same builders the real writes call, for the reason
/// `PriceWritePreview` gives.
public enum ProductWritePreview {
    public static func purchaseWords(
        versionID: String,
        locale: String,
        name: String,
        description: String?
    ) -> String {
        WritePreviewJSON.text(for: ASCClient.productLocalizationBody(
            type: "inAppPurchaseLocalizations",
            versionType: "inAppPurchaseVersions",
            versionID: versionID,
            attributes: ProductLocalizationWrite(
                locale: locale, name: name, description: description
            )
        ))
    }

    public static func subscriptionWords(
        versionID: String,
        locale: String,
        name: String,
        description: String?
    ) -> String {
        WritePreviewJSON.text(for: ASCClient.productLocalizationBody(
            type: "subscriptionLocalizations",
            versionType: "subscriptionVersions",
            versionID: versionID,
            attributes: ProductLocalizationWrite(
                locale: locale, name: name, description: description
            )
        ))
    }

    public static func groupWords(
        versionID: String,
        locale: String,
        name: String,
        customAppName: String?
    ) -> String {
        WritePreviewJSON.text(for: ASCClient.groupLocalizationBody(
            versionID: versionID,
            attributes: GroupLocalizationWrite(
                locale: locale, name: name, customAppName: customAppName
            )
        ))
    }

    public static func purchaseWordsChange(
        id: String,
        name: String?,
        description: String?
    ) -> String {
        WritePreviewJSON.text(for: ASCClient.productLocalizationChange(
            type: "inAppPurchaseLocalizations",
            id: id,
            attributes: ProductLocalizationWrite(name: name, description: description)
        ))
    }

    public static func subscriptionWordsChange(
        id: String,
        name: String?,
        description: String?
    ) -> String {
        WritePreviewJSON.text(for: ASCClient.productLocalizationChange(
            type: "subscriptionLocalizations",
            id: id,
            attributes: ProductLocalizationWrite(name: name, description: description)
        ))
    }

    public static func groupWordsChange(
        id: String,
        name: String?,
        customAppName: String?
    ) -> String {
        WritePreviewJSON.text(for: ASCClient.groupLocalizationChange(
            id: id,
            attributes: GroupLocalizationWrite(name: name, customAppName: customAppName)
        ))
    }
}

/// One way of writing a body out, so two previews cannot format the same
/// request differently.
enum WritePreviewJSON {
    static func text(for value: some Encodable) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(value),
              let text = String(data: data, encoding: .utf8)
        else { return "(could not be written out)" }
        return text
    }
}
