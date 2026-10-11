import Foundation

/// Turns a price plan into one real price per country.
///
/// Pure. Everything it needs arrives as a value, so the whole of the pricing
/// argument can be tested with no network, no key and no files. That matters
/// more here than anywhere else in ASCKit, because the output is money.
///
/// The step that makes this work is the anchor. App Store Connect will say, for
/// the price point you picked in your base territory, which point it considers
/// equivalent in every other country. That answer is already in the right
/// currency, which is the only reason a multiplier can mean anything here.
///
/// It is not a plain conversion, though. Apple converts at its own rate and
/// then works the local sales tax in, so a curve meaning "a fraction of what
/// home pays" has to take that back out first. `USDConversion` is that step, and
/// the curve carries it folded into its multiplier.
public enum PriceResolver {
    /// What one country ends up costing, and why.
    public struct Resolved: Sendable, Hashable, Identifiable {
        public let territory: String
        public let pricePointID: String

        /// What the buyer pays. A real price point, not the target.
        public let customerPrice: Money

        public let currency: String?

        /// What the curve or the override asked for, before rounding.
        public let target: Money

        public let multiplier: Double
        public let source: Source

        /// How much the rounding added to the target. Zero when the ladder had
        /// the exact amount.
        ///
        /// Never negative: rounding only goes up. The one exception is a
        /// country whose whole ladder stops below the target, and `belowTarget`
        /// says when that happened.
        public let roundedUpBy: Money

        /// True when even the top of this country's ladder is under the target,
        /// so the price is the most the store will let you charge there.
        public let belowTarget: Bool

        public var id: String { territory }

        /// Whether the price landed on a `.99` step, which is the one to want.
        public var endsInNinetyNine: Bool { customerPrice.endsInNinetyNine }
    }

    /// Where a price came from, so nobody reads a hand-set number as something
    /// the curve produced.
    public enum Source: Sendable, Hashable {
        /// The base price itself. Only ever the base country, which charges
        /// what you said rather than a multiple of it.
        case base
        /// The curve, and the band it put this country in. Nil for a country
        /// no band names, which takes the curve's base multiplier.
        case curve(band: String?)
        /// An amount somebody typed, rounded up like any other target.
        case overrideAmount
        /// A price point somebody named, taken as given.
        case overridePricePoint

        /// Written out rather than interpolated, because this goes into the
        /// digest and must not depend on how Swift describes an enum.
        public var digestKey: String {
            switch self {
            case .base: "base"
            case let .curve(band): "curve-\(band ?? "unbanded")"
            case .overrideAmount: "override-amount"
            case .overridePricePoint: "override-point"
            }
        }
    }

    public struct Skipped: Sendable, Hashable {
        public let territory: String
        public let reason: LocalizedStringResource

        public init(territory: String, reason: LocalizedStringResource) {
            self.territory = territory
            self.reason = reason
        }

        /// Written by hand over the English, because a
        /// `LocalizedStringResource` is not `Hashable` and because a plan has
        /// to compare the same either side of a change of language.
        public static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.territory == rhs.territory && lhs.reason.english == rhs.reason.english
        }

        public func hash(into hasher: inout Hasher) {
            hasher.combine(territory)
            hasher.combine(reason.english)
        }
    }

    public struct Resolution: Sendable {
        public let productID: String
        public let curveID: String
        public let baseTerritory: String
        public let baseAmount: Money

        /// One per country that got a price, sorted by territory so the digest
        /// does not depend on dictionary order.
        public let prices: [Resolved]

        public let skipped: [Skipped]
        public let problems: [Problem]

        public var hasErrors: Bool { problems.contains { $0.severity == .error } }

        /// What the rounding did, to print above the prices. Carried on the
        /// result rather than left for each caller to remember, because a
        /// rounded price nobody was warned about reads as a mistake.
        public var roundingNote: String { PriceResolver.roundingRule }

        /// The countries where rounding moved the price at all.
        public var rounded: [Resolved] {
            prices.filter(\.roundedUpBy.isPositive)
        }

        /// The countries that did not land on a `.99`, which is every country
        /// whose currency has no minor unit, plus any ladder with no `.99`
        /// above the target.
        public var notEndingInNinetyNine: [Resolved] {
            prices.filter { $0.endsInNinetyNine == false }
        }
    }

    // MARK: - Resolving

    /// - Parameters:
    ///   - anchors: What App Store Connect would charge in each country for the
    ///     base price, keyed by three-letter code. This is Apple's own
    ///     equalization.
    ///   - ladders: Every price point this product offers, keyed by country.
    ///   - territories: Which countries to price. Defaults to the whole table.
    public static func resolve(
        productID: String,
        plan: Product.PricePlan,
        curve: PriceCurve,
        anchors: [String: Money],
        ladders: [String: [PricePoint]],
        territories: [String] = Territory.allIdentifiers,
        path: String? = nil
    ) -> Resolution {
        var prices: [Resolved] = []
        var skipped: [Skipped] = []
        var problems: [Problem] = []

        for territory in territories.sorted() {
            let outcome = resolveOne(Ask(
                territory: territory,
                productID: productID,
                override: plan.overrides[territory],
                curve: curve,
                anchor: anchors[territory],
                ladder: ladders[territory] ?? [],
                path: path,
                baseAmount: plan.baseAmount,
                isBaseTerritory: territory == plan.baseTerritory
            ))
            if let price = outcome.price { prices.append(price) }
            if let left = outcome.skipped { skipped.append(left) }
            problems += outcome.problems
        }

        problems += unexplainedOverrides(in: plan, productID: productID, path: path)

        return Resolution(
            productID: productID,
            curveID: curve.id,
            baseTerritory: plan.baseTerritory,
            baseAmount: plan.baseAmount,
            prices: prices,
            skipped: skipped.sorted { $0.territory < $1.territory },
            problems: problems
        )
    }

    private static func unexplainedOverrides(
        in plan: Product.PricePlan,
        productID: String,
        path: String?
    ) -> [Problem] {
        plan.overrides
            .filter { $0.value.why?.isEmpty ?? true }
            .keys
            .sorted()
            .map { territory in
                Problem(
                    severity: .warning,
                    area: .pricing,
                    message: LocalizedStringResource("""
                    The price for \(territory) is set by hand with no reason \
                    written beside it.
                    """, bundle: .here),
                    fix: LocalizedStringResource("""
                    Add a \"why\" to the override. A price nobody can explain a year \
                    later is the one that goes wrong.
                    """, bundle: .here),
                    productID: productID,
                    territory: territory,
                    path: path,
                    kind: .priceOverrideUnexplained
                )
            }
    }
}
