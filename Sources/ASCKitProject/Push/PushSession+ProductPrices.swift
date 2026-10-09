import ASCKitAPI
import Foundation

/// What one product costs today, and what a price plan would make it cost.
public struct ProductPriceReading: Sendable {
    public let productID: String

    /// The plan the new prices come from. Nil when only the prices of today
    /// were read. It can be a plan that no file holds, for a preview.
    public let plan: Product.PricePlan?

    /// What each country pays today for the whole thing.
    public let current: [String: Money]

    /// What one monthly instalment costs today, where the product is sold
    /// that way.
    public let currentMonthly: [String: Money]

    /// One row per country and plan type, the same rows a push plan holds.
    /// Nil when there is no plan, or when nothing could be worked out, and
    /// then `blocked` says why.
    public let change: ChangePlan.PriceChange?

    /// What the resolver had to say, such as a base price that is not a price
    /// App Store Connect allows.
    public let problems: [Problem]

    public let blocked: [ChangePlan.Blocked]

    /// Where the ladder came from. Nil when there is no plan, because then no
    /// ladder was read.
    public let origin: PriceLadderCache.Origin?

    public init(
        productID: String,
        plan: Product.PricePlan?,
        current: [String: Money],
        currentMonthly: [String: Money] = [:],
        change: ChangePlan.PriceChange? = nil,
        problems: [Problem] = [],
        blocked: [ChangePlan.Blocked] = [],
        origin: PriceLadderCache.Origin? = nil
    ) {
        self.productID = productID
        self.plan = plan
        self.current = current
        self.currentMonthly = currentMonthly
        self.change = change
        self.problems = problems
        self.blocked = blocked
        self.origin = origin
    }
}

public extension PushSession {
    /// Reads the prices of one product, and nothing else.
    ///
    /// The prices of today always come off App Store Connect. With a plan, the
    /// ladder and the anchors for its base price come from `source`, and the
    /// new price in each country is worked out the way a push plan does it.
    /// Nothing is written to the product file. The ladder is kept on disk, so
    /// a plan written later with the same base price needs no second read.
    ///
    /// The status of the product does not matter here. A status decides what
    /// a push may send, and this sends nothing.
    ///
    /// - Parameters:
    ///   - plan: The plan of the product file, a plan nobody wrote yet for a
    ///     preview, or nil for the prices of today only.
    ///   - source: Where the ladder comes from. `.notRead` reads no ladder.
    func readProductPrices(
        of product: Product,
        plan: Product.PricePlan?,
        on match: RemoteProduct,
        source: PriceSource = .cached
    ) async throws -> ProductPriceReading {
        let productID = product.productID

        let today = try await client.currentPrices(for: match)
        let current = today.current.compactMapValues(Money.init(string:))
        let monthly = today.currentMonthly.compactMapValues(Money.init(string:))

        guard let plan, source.wantsPrices else {
            return ProductPriceReading(
                productID: productID, plan: plan, current: current, currentMonthly: monthly
            )
        }

        let rungs = try await ladder(for: plan, on: match, productID: productID, source: source)
        keep(productID: productID, plan: plan, match: match, ladder: rungs, today: (current, monthly))

        var planned = product
        planned.price = plan
        let priced = ProductPlanner.price(
            of: planned,
            against: match,
            prices: ProductPlanner.Prices(
                anchors: [productID: rungs.anchors],
                ladders: [productID: rungs.rungs],
                current: [productID: current],
                currentMonthly: [productID: monthly]
            )
        )

        return ProductPriceReading(
            productID: productID,
            plan: plan,
            current: current,
            currentMonthly: monthly,
            change: priced.plan,
            problems: priced.problems,
            blocked: priced.blocked,
            origin: rungs.origin
        )
    }
}
