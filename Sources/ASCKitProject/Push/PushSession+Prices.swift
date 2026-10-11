import ASCKitAPI
import Foundation

extension PushSession {
    /// Every priced product's ladder, its anchors, and what it costs today.
    ///
    /// One product at a time rather than all at once. A ladder is several
    /// requests on its own, and running twenty products' worth together is how
    /// a rate limit is met.
    ///
    /// What each country pays today is read from App Store Connect for every
    /// product, whatever `source` says. It is one request for a subscription
    /// and three for a purchase, and it is the number a plan calls "old", so a
    /// kept copy would report a rise as no change and the rule guarding a rise
    /// would stop working without saying so.
    func readPrices(
        for onDisk: ProductCatalog,
        on onStore: RemoteProducts,
        source: PriceSource
    ) async throws -> (prices: ProductPlanner.Prices, origins: [String: PriceLadderCache.Origin]) {
        var anchors: [String: [String: Money]] = [:]
        var ladders: [String: [String: [PricePoint]]] = [:]
        var current: [String: [String: Money]] = [:]
        var currentMonthly: [String: [String: Money]] = [:]
        var origins: [String: PriceLadderCache.Origin] = [:]

        let byProductID = onStore.byProductID
        for product in onDisk.sorted {
            guard let match = byProductID[product.productID] else { continue }

            // Today's price, whether or not this project prices the product.
            // A product with no price plan still sells for something, and that
            // number is where somebody pricing it starts.
            let today = try await client.currentPrices(for: match)
            current[product.productID] = today.current.compactMapValues(Money.init(string:))
            currentMonthly[product.productID] = today.currentMonthly
                .compactMapValues(Money.init(string:))

            // The ladder is the expensive half, and only a priced product needs
            // one: nothing works out a price for a product with no plan.
            guard let plan = product.price else { continue }

            let rungs = try await ladder(
                for: plan, on: match, productID: product.productID, source: source
            )
            anchors[product.productID] = rungs.anchors
            ladders[product.productID] = rungs.rungs
            origins[product.productID] = rungs.origin

            keep(
                productID: product.productID,
                plan: plan,
                match: match,
                ladder: rungs,
                today: (current[product.productID] ?? [:],
                        currentMonthly[product.productID] ?? [:])
            )
        }

        return (
            ProductPlanner.Prices(
                anchors: anchors,
                ladders: ladders,
                current: current,
                currentMonthly: currentMonthly
            ),
            origins
        )
    }

    /// One product's ladder, its anchors, and where the two came from.
    struct Ladder {
        let anchors: [String: Money]
        let rungs: [String: [PricePoint]]
        let origin: PriceLadderCache.Origin
    }

    /// One product's ladder and anchors, off the disk when the disk still holds
    /// the right ones, and off App Store Connect otherwise.
    ///
    /// The decision is per product, not per run. A person who changed one base
    /// price pays for that one product and reads the rest off a file.
    func ladder(
        for plan: Product.PricePlan,
        on match: RemoteProduct,
        productID: String,
        source: PriceSource
    ) async throws -> Ladder {
        let identity = RemoteProductIdentity(
            id: match.id, isAutoRenewable: match.isAutoRenewable
        )

        if source == .cached,
           let kept = PriceLadderStore.load(productID: productID, in: project),
           kept.isUsable(for: plan, on: identity, covering: Territory.allIdentifiers) {
            return Ladder(
                anchors: kept.anchors,
                rungs: kept.everyLadder,
                origin: .cache(readOn: kept.readOn)
            )
        }

        let read = try await client.ladderAndAnchors(
            for: match,
            baseTerritory: plan.baseTerritory,
            baseAmount: plan.baseAmount.description,
            territories: Territory.allIdentifiers
        )

        // No currency and no proceeds. A kept ladder cannot hold either, and a
        // plan built from one has to match a plan built from this row for row
        // or the digest a push compares is a digest of something else.
        return Ladder(
            anchors: read.anchors.compactMapValues(Money.init(string:)),
            rungs: Self.pricePoints(from: read.ladders),
            origin: .network
        )
    }

    /// A read ladder as price points, one list per country.
    ///
    /// The command line tool converts a ladder the same way, so a price it
    /// shows is a price a push works from.
    public static func pricePoints(
        from ladders: [String: [RemotePricePoint]]
    ) -> [String: [PricePoint]] {
        ladders.mapValues { rungs in
            rungs.compactMap { rung in
                Money(string: rung.customerPrice).map {
                    PricePoint(id: rung.id, territory: rung.territory, customerPrice: $0)
                }
            }
        }
    }

    /// Keeps what Apple answered, in two files.
    ///
    /// The ladder, with Apple's identifiers, so a window can plan a push
    /// without asking again. And the smaller identifier-free view, so a caller
    /// can price a product with no network and no key.
    ///
    /// A failure here is swallowed. These are caches, the numbers are already
    /// in hand, and a full disk must not stop a push that was going to work.
    ///
    /// A ladder that came off the disk is not written back to it. Nothing about
    /// it changed. What each country pays did, so the small file is written
    /// either way.
    func keep(
        productID: String,
        plan: Product.PricePlan,
        match: RemoteProduct,
        ladder: Ladder,
        today: (current: [String: Money], monthly: [String: Money])
    ) {
        let anchors = ladder.anchors
        let ladders = ladder.rungs

        if ladder.origin == .network {
            try? PriceLadderStore.save(
                PriceLadderCache(
                    productID: productID,
                    remoteProductID: match.id,
                    isAutoRenewable: match.isAutoRenewable,
                    readOn: PriceLadderCache.today(),
                    baseTerritory: plan.baseTerritory,
                    baseAmount: plan.baseAmount,
                    anchors: anchors,
                    ladders: ladders.mapValues { rungs in
                        PriceLadderCache.Steps(
                            ids: rungs.map(\.id), prices: rungs.map(\.customerPrice)
                        )
                    },
                    readForTerritories: Territory.allIdentifiers
                ),
                in: project
            )
        }

        // The prices, not the price points. This is the file an AI reads, and
        // an identifier is the thing a write needs, so the only ones kept are
        // the handful the product file names by hand.
        let named = Set(plan.overrides.values.compactMap(\.pricePoint))

        try? PricePointStore.save(
            PricePointCache(
                productID: productID,
                readOn: PricePointCache.today(),
                baseTerritory: plan.baseTerritory,
                baseAmount: plan.baseAmount,
                anchors: anchors,
                current: today.current,
                currentMonthly: today.monthly,
                ladders: ladders.mapValues { $0.map(\.customerPrice) },
                namedPoints: ladders.values.flatMap(\.self).filter { named.contains($0.id) }
            ),
            in: project
        )
    }
}
