import Foundation

extension PriceResolver {
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
}
