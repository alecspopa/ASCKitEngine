import Foundation

/// Where a read gets its price ladders.
///
/// A ladder is every price App Store Connect will sell one product at: 800
/// steps in each of 177 countries, four batched requests, and the slowest thing
/// ASCKit does. So a project keeps the answer, and this says whether to use it.
///
/// What each country pays today is never one of these. It comes off App Store
/// Connect on every read that asks for prices at all, because it is the number
/// a plan calls "old", and a stale one reports a rise as no change.
public enum PriceSource: String, Sendable, CaseIterable {
    /// Do not read prices at all. What an ordinary read does, and everything
    /// else is somebody asking for them.
    case notRead

    /// The ladder this project already kept, where it is still the right ladder
    /// for this product at this base price. App Store Connect for the rest.
    case cached

    /// App Store Connect, for every priced product, and the kept copy is
    /// written again. What a push reads with, and what Refetch does.
    case fresh

    public var wantsPrices: Bool { self != .notRead }
}
