import Foundation

extension PriceResolver {
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
}
