import Foundation

/// One price App Store Connect is willing to charge for one product in one
/// country.
///
/// You do not set an amount on the App Store. You pick a point off a ladder,
/// and the ladder belongs to the product: the identifier encodes the product,
/// the territory and the step, so a point read from one subscription is not
/// valid on another and a one-time purchase's point is not valid on a
/// subscription at all. Reusing one is a refusal at best and a wrong price at
/// worst.
public struct PricePoint: Codable, Sendable, Hashable, Identifiable {
    /// Apple's opaque identifier. Only ever passed back to Apple.
    public let id: String

    /// The three-letter territory code.
    public let territory: String

    /// What the buyer pays, tax included where the territory includes it.
    public let customerPrice: Money

    /// What Apple pays out. Nil when the ladder was read without it.
    public let proceeds: Money?

    /// The ISO-4217 code the two amounts are in.
    public let currency: String?

    public init(
        id: String,
        territory: String,
        customerPrice: Money,
        proceeds: Money? = nil,
        currency: String? = nil
    ) {
        self.id = id
        self.territory = territory
        self.customerPrice = customerPrice
        self.proceeds = proceeds
        self.currency = currency
    }

    /// Whether the price ends in `.49` or `.99`, the two endings ASCKit lands
    /// on. Apple's ladder holds others too, such as `.90` and `.95`.
    var landsOnALadderEnding: Bool {
        customerPrice.endsInNinetyNine || customerPrice.endsInFortyNine
    }
}
