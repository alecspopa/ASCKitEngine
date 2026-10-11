import Foundation

extension PriceResolver {
    /// What one country works out to. Exactly one of `price` and `skipped` is
    /// filled in, and `problems` says what else is worth knowing either way.
    struct Outcome {
        var price: Resolved?
        var skipped: Skipped?
        var problems: [Problem] = []
    }

    /// Everything one country needs to work out its price, gathered so the
    /// steps below can hand it on without a row of seven arguments.
    struct Ask {
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

    static func resolveOne(_ ask: Ask) -> Outcome {
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
}
