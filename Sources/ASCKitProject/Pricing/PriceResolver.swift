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

    // MARK: - One country

    /// What one country works out to. Exactly one of `price` and `skipped` is
    /// filled in, and `problems` says what else is worth knowing either way.
    private struct Outcome {
        var price: Resolved?
        var skipped: Skipped?
        var problems: [Problem] = []
    }

    /// Everything one country needs to work out its price, gathered so the
    /// steps below can hand it on without a row of seven arguments.
    private struct Ask {
        let territory: String
        let productID: String
        let override: Product.PricePlan.Override?
        let curve: PriceCurve
        let anchor: Money?
        let ladder: [PricePoint]
        let path: String?

        /// The price the whole plan is written from, and whether this country
        /// is the one it is written in.
        let baseAmount: Money
        let isBaseTerritory: Bool

        func problem(
            _ severity: Problem.Severity,
            _ message: LocalizedStringResource,
            fix: LocalizedStringResource,
            kind: Problem.Kind
        ) -> Problem {
            Problem(
                severity: severity,
                area: .pricing,
                message: message,
                fix: fix,
                productID: productID,
                territory: territory,
                path: path,
                kind: kind
            )
        }
    }

    private static func resolveOne(_ ask: Ask) -> Outcome {
        if ask.override?.skip == true {
            return Outcome(skipped: Skipped(
                territory: ask.territory,
                reason: ask.override?.why.map { LocalizedStringResource("\($0)", bundle: .here) }
                    ?? LocalizedStringResource("the file says to leave it out", bundle: .here)
            ))
        }

        var problems: [Problem] = []
        if Territory.isKnown(ask.territory) == false {
            problems.append(ask.problem(
                .warning,
                LocalizedStringResource("""
                App Store Connect sells in \(ask.territory), and ASCKit's table does not \
                list it. It gets Apple's own price.
                """, bundle: .here),
                fix: LocalizedStringResource(
                    "Nothing here. ASCKit needs the territory added to its own table.", bundle: .here
                ),
                kind: .territoryNotKnown
            ))
        }

        guard ask.ladder.isEmpty == false else {
            problems.append(ask.problem(
                .error,
                LocalizedStringResource(
                    "\(ask.productID) has no prices to choose from in \(ask.territory).", bundle: .here
                ),
                fix: LocalizedStringResource("""
                Read App Store Connect again. A product only has a price ladder once \
                the store knows about it.
                """, bundle: .here),
                kind: .noPricePoint
            ))
            return Outcome(problems: problems)
        }

        if ask.override?.pricePoint != nil {
            return namedPoint(ask, alreadyFound: problems)
        }

        guard let wanted = target(for: ask) else {
            return Outcome(
                skipped: Skipped(
                    territory: ask.territory,
                    reason: LocalizedStringResource(
                        "App Store Connect gave no equivalent price here", bundle: .here
                    )
                ),
                problems: problems
            )
        }
        return rounded(ask, to: wanted, alreadyFound: problems)
    }

    /// A price point somebody named, taken as given. It has to belong to this
    /// product in this country: a point from anywhere else is a wrong price
    /// rather than a near miss.
    private static func namedPoint(_ ask: Ask, alreadyFound: [Problem]) -> Outcome {
        var problems = alreadyFound
        guard let named = ask.override?.pricePoint else { return Outcome(problems: problems) }

        guard let point = ask.ladder.first(where: { $0.id == named }) else {
            problems.append(ask.problem(
                .error,
                LocalizedStringResource(
                    "\(ask.productID) has no price point \(named) in \(ask.territory).", bundle: .here
                ),
                fix: LocalizedStringResource("""
                A price point belongs to one product in one country. Take this one out, \
                or set an amount instead and let ASCKit find the point.
                """, bundle: .here),
                kind: .noPricePoint
            ))
            return Outcome(problems: problems)
        }

        return Outcome(
            price: Resolved(
                territory: ask.territory,
                pricePointID: point.id,
                customerPrice: point.customerPrice,
                currency: point.currency,
                target: point.customerPrice,
                multiplier: 1.0,
                source: .overridePricePoint,
                roundedUpBy: Money(0),
                belowTarget: false
            ),
            problems: problems
        )
    }

    /// What a country should cost before rounding, and where the number came
    /// from.
    private struct Target {
        let amount: Money
        let multiplier: Double
        let source: Source
    }

    /// Nil when Apple gave no equivalent price to multiply.
    private static func target(for ask: Ask) -> Target? {
        if let amount = ask.override?.amount {
            return Target(amount: amount, multiplier: 1.0, source: .overrideAmount)
        }

        // The base country charges the base price, whatever the curve says
        // about it. You named that price for that country, so multiplying it by
        // anything would mean the number you wrote is not the number you get.
        if ask.isBaseTerritory {
            return Target(amount: ask.baseAmount, multiplier: 1.0, source: .base)
        }

        guard let anchor = ask.anchor else { return nil }

        let multiplier = ask.curve.multiplier(for: ask.territory)
        return Target(
            amount: anchor.scaled(by: multiplier),
            multiplier: multiplier,
            source: .curve(band: ask.curve.reason(for: ask.territory))
        )
    }

    private static func rounded(
        _ ask: Ask,
        to wanted: Target,
        alreadyFound: [Problem]
    ) -> Outcome {
        var problems = alreadyFound
        // A typed amount that is a step is taken as it is. A curve that
        // lands on a step such as .90 still rounds up to a .99.
        var typed = true
        if case .curve = wanted.source { typed = false }
        guard let point = roundedUp(from: wanted.amount, in: ask.ladder, takesAnyExactStep: typed) else {
            return Outcome(problems: problems)
        }

        let belowTarget = point.customerPrice < wanted.amount
        if belowTarget {
            problems.append(ask.problem(
                .warning,
                LocalizedStringResource("""
                \(ask.productID) asks for \(wanted.amount.description) in \(ask.territory), and the most \
                the store sells for there is \(point.customerPrice.description).
                """, bundle: .here),
                fix: LocalizedStringResource("""
                The price is the top of that country's ladder. Lower the base price, or \
                leave the country out.
                """, bundle: .here),
                kind: .noPricePoint
            ))
        }

        return Outcome(
            price: Resolved(
                territory: ask.territory,
                pricePointID: point.id,
                customerPrice: point.customerPrice,
                currency: point.currency,
                target: wanted.amount,
                multiplier: wanted.multiplier,
                source: wanted.source,
                roundedUpBy: Money(point.customerPrice.distance(to: wanted.amount)),
                belowTarget: belowTarget
            ),
            problems: problems
        )
    }

    // MARK: - The instalment

    /// The most twelve instalments may come to, against the price of the year.
    ///
    /// Apple: "The 12-month commitment total must be greater than or equal to
    /// the upfront price, and less than or equal to 1.5 times the upfront
    /// price." So paying monthly may cost up to half as much again as paying at
    /// once, and may never cost less.
    ///
    /// Break the upper bound and the write comes back
    /// `INVALID_PRICE_TOO_HIGH`, naming the price you sent when the one that is
    /// too high is the instalment you left alone. Lowering a yearly price
    /// without lowering the instalment breaks it every time.
    ///
    /// Measured before it was found written down, by sending 174 countries and
    /// reading which came back: everything with a year worth 0.666 of twelve
    /// instalments or more landed, everything at 0.656 or less was refused. Two
    /// thirds is one over 1.5, so the measurement and the rule agree exactly.
    public static let mostTwelveInstalmentsMayCost = Decimal(3) / 2

    /// What one instalment becomes when the yearly price moves.
    ///
    /// The same scale as the year. Whatever factor the yearly price moved by,
    /// the instalment moves by too, so a country keeps the split it already
    /// offers between paying at once and paying monthly.
    ///
    /// Then it is pulled back inside the band Apple allows, because rounding
    /// can push it out either way. A plan App Store Connect would refuse is
    /// worth catching here rather than in the reply.
    public static func instalment(
        matching yearly: Money,
        wasYearly: Money,
        wasInstalment: Money,
        in ladder: [PricePoint]
    ) -> PricePoint? {
        guard wasYearly.isPositive else { return nil }

        let factor = yearly.amount / wasYearly.amount
        let target = Money(wasInstalment.amount * factor)

        // Sorted by the identifier as well as the price. Swift does not sort
        // stably, and a ladder holds several points at one price, so sorting on
        // the price alone lets the same ladder in a different order pick a
        // different identifier for the same money.
        // The .49 and .99 steps, as for the year. All the steps when none of
        // those fit the band, because an instalment Apple refuses is worse
        // than one with another ending.
        let fitting = ladder
            .filter { fits(yearly: yearly, instalment: $0.customerPrice) }
            .sorted { ($0.customerPrice, $0.id) < ($1.customerPrice, $1.id) }
        let landing = fitting.filter(\.landsOnALadderEnding)
        let allowed = landing.isEmpty ? fitting : landing

        // The dearest allowed instalment that is no more than the scaled
        // target, which keeps the split as close to today's as the ladder
        // permits. Failing that, the cheapest the rule allows at all.
        return allowed.last { $0.customerPrice <= target } ?? allowed.first
    }

    /// Whether a yearly price and an instalment can go out together.
    ///
    /// Both bounds. The instalment can be too cheap as well as too dear: twelve
    /// of them must come to at least the price of the year, or paying monthly
    /// would undercut paying at once.
    public static func fits(yearly: Money, instalment: Money) -> Bool {
        guard instalment.isPositive else { return true }
        let commitment = instalment.amount * 12
        return commitment >= yearly.amount
            && commitment <= mostTwelveInstalmentsMayCost * yearly.amount
    }

    // MARK: - Rounding

    /// What the rounding does, in one sentence, for anything that shows a price
    /// to a person.
    ///
    /// One place, so the plan, the command line and the app all say it the same
    /// way, and nobody meets a rounded price without having been told.
    public static var roundingRule: String {
        String(localized: """
        You cannot charge any amount you like. The App Store offers a fixed ladder \
        of prices in each country. ASCKit uses only its steps that end in .49 or \
        .99, rounds every price up to the next one, and goes on from a .49 to the \
        .99 above it. In a currency with no such steps, ASCKit takes the next step up.
        """, bundle: .module)
    }

    /// The price to charge for a target: the next `.49` or `.99` step up, and
    /// the `.99` above a `.49`.
    ///
    /// Up, not nearest. Rounding down charges less than the curve asked for, so
    /// a 0.55 multiplier quietly becomes something lower, and the money lost is
    /// real.
    ///
    /// Only the `.49` and `.99` steps. Apple's ladder holds many more: in
    /// dollars it goes 1.89, 1.90, 1.95, 1.99, and above 50 it goes .90, .99.
    /// Those are real prices, but ASCKit says it lands on `.49` and `.99`, so
    /// the other steps are left out. Then up again past a `.49` step, because
    /// `.99` is the ending to land on. One step and no further, so rounding
    /// cannot skip a whole tier looking for an ending it likes.
    ///
    /// A currency with no `.49` or `.99` step, such as the yen or the Swiss
    /// franc, takes the next step up of all its steps.
    ///
    /// - Parameter takesAnyExactStep: Whether a target that is already a step
    ///   is taken as it is, whatever it ends in. True for an amount somebody
    ///   typed, who meant that price. False for a curve, which must land on
    ///   `.49` or `.99` like any other target.
    public static func roundedUp(
        from target: Money,
        in ladder: [PricePoint],
        takesAnyExactStep: Bool = true
    ) -> PricePoint? {
        // By the identifier as well, for the reason `instalment` sorts that
        // way: an unstable sort would let the input order decide which of two
        // points at one price this returns.
        let ordered = ladder.sorted { ($0.customerPrice, $0.id) < ($1.customerPrice, $1.id) }
        guard ordered.isEmpty == false else { return nil }

        if takesAnyExactStep, let exact = ordered.first(where: { $0.customerPrice == target }) {
            return exact
        }

        let steps = landingSteps(in: ordered)
        let above = steps.drop { $0.customerPrice < target }

        // No step ASCKit lands on reaches the target. Any step that does is
        // better than charging less, and failing that the top step is as close
        // as this country can get, and the resolver says so.
        guard let first = above.first else {
            return ordered.first { $0.customerPrice >= target } ?? ordered.last
        }

        if first.customerPrice.endsInNinetyNine { return first }
        if let next = above.dropFirst().first, next.customerPrice.endsInNinetyNine {
            return next
        }
        return first
    }

    /// The steps a price may land on: the `.49` and `.99` ones, or every step
    /// in a currency that has none of those.
    static func landingSteps(in ladder: [PricePoint]) -> [PricePoint] {
        let ends = ladder.filter(\.landsOnALadderEnding)
        return ends.isEmpty ? ladder : ends
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
