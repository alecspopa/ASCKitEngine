import ASCKitAPI
import Foundation

/// Writes the in-app purchases to App Store Connect.
///
/// Works from a plan rather than from the files, so what goes out is exactly
/// what somebody read before agreeing to it.
public struct ProductPusher: Sendable {
    /// What a write of the prices did.
    ///
    /// Both kinds go in one request, so a run wrote everything or wrote
    /// nothing. Probably nothing, on a refusal: Apple never says that a
    /// rejected request of this shape is applied all or nothing, so a failure
    /// here is a reason to read the prices back rather than a promise that they
    /// are untouched.
    ///
    /// A country that failed is worth as much as one that went, which is what
    /// the one-country-at-a-time path reports.
    public struct PriceResult: Sendable {
        public var written: [Written] = []
        public var failed: [Failure] = []

        /// The bodies a dry run would have sent, in the order it would have
        /// sent them.
        public var wouldSend: [String] = []

        public var isCompleteSuccess: Bool { failed.isEmpty }

        /// The countries to try again, for a message that tells somebody what
        /// to do rather than only what went wrong.
        public var retryable: [String] {
            failed.map(\.what).filter { $0.isEmpty == false }
        }
    }

    public struct Written: Sendable, Hashable {
        public let productID: String
        public let territory: String
        public let planType: String
        public let currency: String?
        public let from: String?
        public let to: String
        public let pricePointID: String
        public let preservedCurrentPrice: Bool?
    }

    public struct Failure: Sendable, Hashable {
        public let productID: String

        /// A language, or a country, or empty when the whole product failed.
        public let what: String

        /// What App Store Connect said, in its own words.
        public let reason: String
    }

    /// Not private, because the words half lives in `ProductPusherWords.swift`.
    ///
    /// Not public either, which is what keeps the synthesized initializer
    /// inside the package: every push goes through `PushSession` and leaves a
    /// record behind.
    let client: ASCClient

    // MARK: - Prices

    /// One country failing does not stop the rest, and the receipt says which
    /// ones went so a second run writes only what is left.
    /// - Parameter oneCountryAtATime: Write a subscription's countries one
    ///   request each rather than all in one. Slower, and the only way to find
    ///   out which country the store objected to when the one request is
    ///   refused without saying.
    func pushPrices(
        _ plan: ChangePlan,
        to remote: RemoteProducts,
        dryRun: Bool = false,
        oneCountryAtATime: Bool = false,
        progress: (@Sendable (String) -> Void)? = nil
    ) async -> PriceResult {
        var result = PriceResult()
        let byProductID = remote.byProductID

        for change in plan.pricePlans where change.changing.isEmpty == false {
            guard let product = byProductID[change.productID] else {
                result.failed.append(Failure(
                    productID: change.productID,
                    what: "",
                    reason: "App Store Connect no longer has this in-app purchase."
                ))
                continue
            }

            if change.replacesWholeSchedule {
                await replaceSchedule(
                    change, of: product, dryRun: dryRun, progress: progress, into: &result
                )
            } else if oneCountryAtATime {
                await writeEachCountry(
                    change, of: product, dryRun: dryRun, progress: progress, into: &result
                )
            } else {
                await writeEveryCountry(
                    change, of: product, dryRun: dryRun, progress: progress, into: &result
                )
            }
        }
        return result
    }

    /// A one-time purchase, in one request carrying every country.
    ///
    /// Every country, including the ones that do not change. Posting a schedule
    /// replaces the one before it, so a country left out of this body goes back
    /// to Apple's equalized price.
    private func replaceSchedule(
        _ change: ChangePlan.PriceChange,
        of product: RemoteProduct,
        dryRun: Bool,
        progress: (@Sendable (String) -> Void)?,
        into result: inout PriceResult
    ) async {
        let prices = change.rows.map {
            PriceWrite(territory: $0.territory, pricePointID: $0.pricePointID)
        }

        if dryRun {
            result.wouldSend.append(PriceWritePreview.priceSchedule(
                purchaseID: product.id,
                baseTerritory: change.baseTerritory,
                prices: prices
            ))
            return
        }

        progress?("\(change.productID), \(prices.count) countries in one request")
        do {
            try await client.createPriceSchedule(
                purchaseID: product.id,
                baseTerritory: change.baseTerritory,
                prices: prices
            )
            result.written += change.changing.map { written($0, of: change) }
        } catch {
            // The whole schedule goes in one request, so it either all lands or
            // none of it does. There is nothing partial to report.
            result.failed.append(Failure(
                productID: change.productID,
                what: "",
                reason: ErrorMessage.text(for: error)
            ))
        }
    }

    /// A subscription, every country in one request.
    ///
    /// Every country, including the ones that do not change, for the same
    /// reason a one-time purchase sends all of them. Apple documents this
    /// update but never says whether it replaces the price set or adds to it,
    /// and sending all of them is right either way. Sending only the changes
    /// would empty every other country if it replaces.
    private func writeEveryCountry(
        _ change: ChangePlan.PriceChange,
        of product: RemoteProduct,
        dryRun: Bool,
        progress: (@Sendable (String) -> Void)?,
        into result: inout PriceResult
    ) async {
        let preserving = change.preserveCurrentPrice ?? true
        let prices = change.rows.map {
            PriceWrite(
                territory: $0.territory,
                pricePointID: $0.pricePointID,
                planType: $0.planType.rawValue
            )
        }

        if dryRun {
            result.wouldSend.append(PriceWritePreview.subscriptionPrices(
                subscriptionID: product.id,
                prices: prices,
                preserveCurrentPrice: preserving
            ))
            return
        }

        progress?("\(change.productID), \(prices.count) countries in one request")
        do {
            try await client.updateSubscriptionPrices(
                subscriptionID: product.id,
                prices: prices,
                preserveCurrentPrice: preserving
            )
            result.written += change.changing.map { written($0, of: change) }
        } catch {
            // Careful with the wording. One request refused is probably one
            // request that changed nothing, but Apple does not say that a
            // rejected compound update is applied all or nothing, and probably
            // is not a word to put next to money. Reading it back is the only
            // way to know, and running again does exactly that.
            result.failed.append(Failure(
                productID: change.productID,
                what: "",
                reason: ErrorMessage.text(for: error)
                    + """
                     Nothing is known to have been written, but read it back rather than \
                    assuming: run asckit diff --prices, or run this again, which reads \
                    first and writes only what is still wrong. \
                    --one-country-at-a-time says which country the store objected to.
                    """
            ))
        }
    }

    /// How many countries to write at once.
    ///
    /// A subscription has no bulk write, so a change everywhere is one request
    /// per country and doing them in a row takes a minute and a half. Six at a
    /// time takes about fifteen seconds and uses the same four percent of the
    /// hourly allowance either way, because the allowance counts requests
    /// rather than time.
    ///
    /// Not more, because these are writes. A rate limit met by six requests in
    /// flight is six that have to be waited out, and `RateLimitGate` is shared
    /// so they all wait together.
    static let countriesAtOnce = 6

    /// A subscription, one request per country that changes.
    ///
    /// A country left out keeps what it has, so only the ones that move are
    /// written. One failing does not stop the rest: running the push again
    /// reads the prices back and writes only what is still wrong.
    private func writeEachCountry(
        _ change: ChangePlan.PriceChange,
        of product: RemoteProduct,
        dryRun: Bool,
        progress: (@Sendable (String) -> Void)?,
        into result: inout PriceResult
    ) async {
        let preserving = change.preserveCurrentPrice ?? true
        let rows = change.changing

        guard dryRun == false else {
            result.wouldSend += rows.map { row in
                PriceWritePreview.subscriptionPrice(
                    subscriptionID: product.id,
                    price: PriceWrite(
                        territory: row.territory,
                        pricePointID: row.pricePointID,
                        planType: row.planType.rawValue
                    ),
                    preserveCurrentPrice: preserving
                )
            }
            return
        }

        var outcomes = await withTaskGroup(
            of: (row: ChangePlan.PriceChange.Row, failure: String?).self
        ) { group in
            var started = 0
            var finished: [(row: ChangePlan.PriceChange.Row, failure: String?)] = []

            func start(_ row: ChangePlan.PriceChange.Row) {
                group.addTask {
                    progress?("\(change.productID), \(row.territory)")
                    do {
                        try await client.createSubscriptionPrice(
                            subscriptionID: product.id,
                            price: PriceWrite(
                                territory: row.territory, pricePointID: row.pricePointID
                            ),
                            preserveCurrentPrice: preserving
                        )
                        return (row, nil)
                    } catch {
                        return (row, ErrorMessage.text(for: error))
                    }
                }
            }

            while started < min(Self.countriesAtOnce, rows.count) {
                start(rows[started])
                started += 1
            }
            for await outcome in group {
                finished.append(outcome)
                if started < rows.count {
                    start(rows[started])
                    started += 1
                }
            }
            return finished
        }

        // They come back in whatever order they finished, and a receipt that
        // lists countries in a different order every run is one nobody can
        // compare against the last.
        outcomes.sort { $0.row.territory < $1.row.territory }

        for outcome in outcomes {
            if let failure = outcome.failure {
                result.failed.append(Failure(
                    productID: change.productID,
                    what: outcome.row.territory,
                    reason: failure
                ))
            } else {
                result.written.append(written(outcome.row, of: change))
            }
        }
    }

    private func written(
        _ row: ChangePlan.PriceChange.Row,
        of change: ChangePlan.PriceChange
    ) -> Written {
        Written(
            productID: change.productID,
            territory: row.territory,
            planType: row.planType.rawValue,
            currency: row.currency,
            from: row.oldAmount?.description,
            to: row.newAmount.description,
            pricePointID: row.pricePointID,
            preservedCurrentPrice: change.preserveCurrentPrice
        )
    }
}

public enum ProductPushError: Error, CustomLocalizedStringResourceConvertible {
    case noNameToCreateWith(locale: String)

    /// App Store Connect holds no version of this product's words at all.
    ///
    /// A new draft copies the version before it, so there is nothing to copy.
    /// A person makes the first words in App Store Connect.
    case noDraft(locales: [String])

    /// App Review has the words now, or a review submission holds them, so
    /// App Store Connect takes no change and no new draft.
    case versionIsClosed(locales: [String], state: String)

    /// App Store Connect did not make the new draft the words needed.
    case newDraftRefused(locales: [String], reason: String)

    case nothingRead

    public var localizedStringResource: LocalizedStringResource {
        switch self {
        case let .noDraft(locales):
            LocalizedStringResource("""
            App Store Connect holds no draft of this product's words. Make one there, \
            then push again. Nothing was written in \(locales.formatted(.list(type: .and))).
            """, bundle: .here)
        case let .versionIsClosed(locales, state):
            LocalizedStringResource("""
            The words of this product are in a version that is \(state), and App \
            Store Connect takes no change to it now. Nothing was written in \
            \(locales.formatted(.list(type: .and))).
            """, bundle: .here)
        case let .newDraftRefused(locales, reason):
            LocalizedStringResource("""
            App Store Connect did not make a new draft of this product's words. \
            \(reason) Nothing was written in \(locales.formatted(.list(type: .and))).
            """, bundle: .here)
        case let .noNameToCreateWith(locale):
            LocalizedStringResource("""
            \(locale) has no name, and App Store Connect needs one to make a language.
            """, bundle: .here)
        case .nothingRead:
            LocalizedStringResource("""
            The in-app purchases were not read, so there is nothing to write. \
            Read App Store Connect first.
            """, bundle: .here)
        }
    }
}

extension ProductPushError: CustomStringConvertible {
    public var description: String { String(localized: localizedStringResource) }
}
