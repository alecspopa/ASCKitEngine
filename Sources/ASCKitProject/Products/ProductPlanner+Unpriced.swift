import Foundation

/// The countries of a price plan that have no price, and what the plan says
/// about them.
extension ProductPlanner {
    /// How many countries a message names before it says "and other
    /// countries".
    static let mostCountriesNamed = 10

    /// The countries with no price that ASCKit worked out, and that the file
    /// does not skip on purpose.
    ///
    /// A push sends a price for every country it has one for. A country it
    /// leaves out of a purchase's schedule goes to whatever App Store Connect
    /// picks, which is a price nobody saw. So nothing goes until every country
    /// has a price on screen, or the file skips it on purpose.
    static func unpricedCountries(
        plan: Product.PricePlan,
        asked: [String],
        rows: [ChangePlan.PriceChange.Row]
    ) -> [String] {
        let skippedOnPurpose = Set(plan.overrides.filter { $0.value.skip == true }.keys)
        let priced = Set(rows.map(\.territory))
        return Set(asked).subtracting(priced).subtracting(skippedOnPurpose).sorted()
    }

    /// What the plan says about those countries, so the publish sheet names
    /// them.
    static func blocked(_ productID: String, unpriced: [String]) -> [ChangePlan.Blocked] {
        guard unpriced.isEmpty == false else { return [] }

        return [ChangePlan.Blocked(
            reason: reason(productID, unpriced: unpriced),
            affects: LocalizedStringResource("the price of \(productID)", bundle: .here),
            cause: .product,
            parts: [.prices]
        )]
    }

    /// The sentence, with at most ten countries named. A base price off the
    /// ladder leaves every country but one, and a list of 174 codes says
    /// nothing the first few do not.
    ///
    /// Two returns rather than an if expression, so the extractor reaches
    /// both sentences.
    private static func reason(_ productID: String, unpriced: [String]) -> LocalizedStringResource {
        let named = unpriced.prefix(mostCountriesNamed).formatted(.list(type: .and))
        if unpriced.count > mostCountriesNamed {
            return LocalizedStringResource("""
            ASCKit has no price for \(productID) in \(named) and other countries. \
            App Store Connect would choose those prices itself, so no price goes until \
            each of them has one. Use a base price that App Store Connect allows, or \
            set those countries by hand.
            """, bundle: .here)
        }
        return LocalizedStringResource("""
        ASCKit has no price for \(productID) in \(named). \
        App Store Connect would choose those prices itself, so no price goes until \
        each of them has one. Use a base price that App Store Connect allows, or \
        set those countries by hand.
        """, bundle: .here)
    }
}
