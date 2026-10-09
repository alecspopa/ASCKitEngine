import Foundation

/// One in-app purchase, as `products/<productId>.json`.
///
/// Products sit beside `asckit.json` rather than inside a version folder,
/// because a product is not tied to a version. It hangs off the app, its
/// localisations relate to the product, and its price takes effect on the date
/// the price says. Putting one copy in every version folder would let two
/// folders disagree about the price of one product, with nothing saying which
/// is true.
public struct Product: Codable, Sendable, Hashable, Identifiable {
    /// The string the app's own source asks the store for. It is permanent, it
    /// is what a person searches for, and it is the file name.
    public var productID: String

    /// Held as a string rather than as `Kind`, so a word nobody recognises is
    /// reported by the validator with the file saying what it says, instead of
    /// failing to decode and taking the whole project with it. That is the rule
    /// `deviceClasses` and `primaryCategory` already follow.
    public var kind: String

    /// The internal name, which only App Store Connect shows.
    public var referenceName: String?

    /// The group this subscription belongs to. Subscriptions only.
    public var subscriptionGroup: String?

    /// `ONE_MONTH`, `ONE_YEAR`. Subscriptions only.
    public var subscriptionPeriod: String?

    public var familySharable: Bool?

    public var status: AppInformation.Status

    public var reviewNote: String?

    public var price: PricePlan?

    /// Keyed by locale. A language that is not here is left alone on App Store
    /// Connect.
    public var localizations: [String: Localization]

    public var id: String { productID }

    /// The kind, as far as it is a word ASCKit knows. An unrecognised word
    /// reads as nil here and is reported by the validator, so nothing
    /// downstream has to decide what a kind it cannot place means. It decides
    /// how a price is written, and guessing that wrong reprices every country.
    public var resolvedKind: Kind? { Kind(rawValue: kind) }

    /// How often it renews, in words. Nil for anything but a subscription.
    ///
    /// A period Apple adds later reads as itself rather than as nothing,
    /// because a window showing ONE_DECADE is better than one showing a gap.
    public var subscriptionPeriodName: String? {
        guard let subscriptionPeriod else { return nil }
        guard let name = Self.periodNames[subscriptionPeriod] else { return subscriptionPeriod }
        return String(localized: name)
    }

    private static let periodNames: [String: LocalizedStringResource] = [
        "ONE_WEEK": LocalizedStringResource("1 week", bundle: .here),
        "ONE_MONTH": LocalizedStringResource("1 month", bundle: .here),
        "TWO_MONTHS": LocalizedStringResource("2 months", bundle: .here),
        "THREE_MONTHS": LocalizedStringResource("3 months", bundle: .here),
        "SIX_MONTHS": LocalizedStringResource("6 months", bundle: .here),
        "ONE_YEAR": LocalizedStringResource("1 year", bundle: .here)
    ]

    // MARK: - Pieces

    public enum Kind: String, Sendable, CaseIterable, Codable {
        case consumable
        case nonConsumable = "non_consumable"
        case nonRenewingSubscription = "non_renewing_subscription"
        case autoRenewableSubscription = "auto_renewable_subscription"

        public var displayName: String {
            switch self {
            case .consumable: String(localized: "Consumable", bundle: .module)
            case .nonConsumable: String(localized: "Non-consumable", bundle: .module)
            case .nonRenewingSubscription: String(localized: "Non-renewing subscription", bundle: .module)
            case .autoRenewableSubscription: String(localized: "Auto-renewable subscription", bundle: .module)
            }
        }

        /// Only an auto-renewable subscription belongs to a group, keeps its
        /// prices per territory, and can preserve what current customers pay.
        public var isAutoRenewable: Bool { self == .autoRenewableSubscription }

        /// Whether writing a price replaces every territory at once.
        ///
        /// True for everything but an auto-renewable subscription. A one-time
        /// purchase has one price schedule and posting a new one throws the old
        /// one away, so a territory left out goes back to Apple's equalized
        /// price. A subscription has no schedule at all: each territory is its
        /// own write, and a territory left out keeps what it has.
        ///
        /// The two rules are opposite, and confusing them reprices a hundred
        /// countries without saying so.
        public var priceWriteReplacesEveryTerritory: Bool { isAutoRenewable == false }

        public static var allIdentifiers: [String] { allCases.map(\.rawValue) }
    }

    /// What this product should cost, everywhere.
    public struct PricePlan: Codable, Sendable, Hashable {
        /// The territory the base amount is in, as a three-letter code.
        public var baseTerritory: String

        public var baseAmount: Money

        /// The curve's identifier, or one of its aliases. Held as a string for
        /// the same reason `kind` is.
        public var curve: String

        /// Whether people who already subscribe keep what they pay.
        ///
        /// Subscriptions only, and true unless somebody says otherwise. False
        /// on a rise puts every existing subscriber into Apple's consent flow:
        /// they are emailed, they have to agree, and the ones who do not answer
        /// are cancelled at renewal. That is churn, and it cannot be undone.
        public var preserveCurrentPrice: Bool?

        /// `2026-09-01`, or nil for as soon as the write lands.
        public var startDate: String?

        /// Territories set by hand rather than by the curve, keyed by
        /// three-letter code.
        public var overrides: [String: Override]

        public struct Override: Codable, Sendable, Hashable {
            /// The customer price to aim for, rounded up to a real price point
            /// the way a curve's result is. An amount the store already offers
            /// is taken as it is.
            public var amount: Money?

            /// An exact price point id, taken as given. For a price copied off
            /// App Store Connect rather than worked out.
            public var pricePoint: String?

            /// Leave this territory out of the write.
            public var skip: Bool?

            /// Why this territory is not on the curve. A price nobody can
            /// explain a year later is the one that goes wrong, so a missing
            /// reason is a warning.
            public var why: String?

            public init(
                amount: Money? = nil,
                pricePoint: String? = nil,
                skip: Bool? = nil,
                why: String? = nil
            ) {
                self.amount = amount
                self.pricePoint = pricePoint
                self.skip = skip
                self.why = why
            }

            /// True when the override says nothing about what to charge.
            public var isEmpty: Bool {
                amount == nil && pricePoint == nil && skip != true
            }
        }

        public init(
            baseTerritory: String,
            baseAmount: Money,
            curve: String,
            preserveCurrentPrice: Bool? = nil,
            startDate: String? = nil,
            overrides: [String: Override] = [:]
        ) {
            self.baseTerritory = baseTerritory
            self.baseAmount = baseAmount
            self.curve = curve
            self.preserveCurrentPrice = preserveCurrentPrice
            self.startDate = startDate
            self.overrides = overrides
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            baseTerritory = try container.decode(String.self, forKey: .baseTerritory)
            baseAmount = try container.decode(Money.self, forKey: .baseAmount)
            curve = try container.decodeIfPresent(String.self, forKey: .curve)
                ?? PriceCurve.appleEqualized.id
            preserveCurrentPrice = try container.decodeIfPresent(
                Bool.self, forKey: .preserveCurrentPrice
            )
            startDate = try container.decodeIfPresent(String.self, forKey: .startDate)
            overrides = try container.decodeIfPresent(
                [String: Override].self, forKey: .overrides
            ) ?? [:]
        }

        /// Subscribers keep what they pay unless the file says otherwise.
        public var preservesCurrentPrice: Bool { preserveCurrentPrice ?? true }
    }

    /// One language's name and description for this product.
    public struct Localization: Codable, Sendable, Hashable {
        public var name: String?
        public var description: String?

        public init(name: String? = nil, description: String? = nil) {
            self.name = name
            self.description = description
        }

        public subscript(field: ProductField) -> String? {
            get {
                switch field {
                case .name: name
                case .description: description
                }
            }
            set {
                switch field {
                case .name: name = newValue
                case .description: description = newValue
                }
            }
        }

        /// Only the fields this language sets.
        public var presentFields: [ProductField] {
            ProductField.allCases.filter { self[$0] != nil }
        }
    }

    // MARK: - Reading and writing

    private enum CodingKeys: String, CodingKey {
        case productID = "productId"
        case kind, referenceName, subscriptionGroup, subscriptionPeriod
        case familySharable, status, reviewNote, price, localizations
    }

    public init(
        productID: String,
        kind: String,
        referenceName: String? = nil,
        subscriptionGroup: String? = nil,
        subscriptionPeriod: String? = nil,
        familySharable: Bool? = nil,
        status: AppInformation.Status = .draft,
        reviewNote: String? = nil,
        price: PricePlan? = nil,
        localizations: [String: Localization] = [:]
    ) {
        self.productID = productID
        self.kind = kind
        self.referenceName = referenceName
        self.subscriptionGroup = subscriptionGroup
        self.subscriptionPeriod = subscriptionPeriod
        self.familySharable = familySharable
        self.status = status
        self.reviewNote = reviewNote
        self.price = price
        self.localizations = localizations
    }

    /// Every key but the product and its kind has a default, so a file written
    /// by hand does not have to say everything. That is the rule
    /// `ProjectConfig` follows.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        productID = try container.decode(String.self, forKey: .productID)
        kind = try container.decode(String.self, forKey: .kind)
        referenceName = try container.decodeIfPresent(String.self, forKey: .referenceName)
        subscriptionGroup = try container.decodeIfPresent(
            String.self, forKey: .subscriptionGroup
        )
        subscriptionPeriod = try container.decodeIfPresent(
            String.self, forKey: .subscriptionPeriod
        )
        familySharable = try container.decodeIfPresent(Bool.self, forKey: .familySharable)
        status = try container.decodeIfPresent(
            AppInformation.Status.self, forKey: .status
        ) ?? .draft
        reviewNote = try container.decodeIfPresent(String.self, forKey: .reviewNote)
        price = try container.decodeIfPresent(PricePlan.self, forKey: .price)
        localizations = try container.decodeIfPresent(
            [String: Localization].self, forKey: .localizations
        ) ?? [:]
    }
}
