import ASCKitAPI
import Foundation

/// Works out what a push would do to the in-app purchases.
///
/// Pure, like `Planner`. Everything it needs arrives as a value, including the
/// price ladders, so the whole of what goes out can be checked with no network.
public enum ProductPlanner {
    /// Where a product's price ladder and Apple's equivalent prices come from.
    ///
    /// Read separately from the catalogue, because a ladder is thousands of
    /// rows per product and nobody wants that every time a window opens.
    public struct Prices: Sendable {
        /// What App Store Connect would charge in each country for the base
        /// price, keyed by product then by country.
        public let anchors: [String: [String: Money]]

        /// Every price this product can be sold at, keyed by product then by
        /// country.
        public let ladders: [String: [String: [PricePoint]]]

        /// What each country pays today, keyed by product then by country.
        public let current: [String: [String: Money]]

        /// What one instalment costs today, where the product is sold that way.
        public let currentMonthly: [String: [String: Money]]

        public init(
            anchors: [String: [String: Money]] = [:],
            ladders: [String: [String: [PricePoint]]] = [:],
            current: [String: [String: Money]] = [:],
            currentMonthly: [String: [String: Money]] = [:]
        ) {
            self.anchors = anchors
            self.ladders = ladders
            self.current = current
            self.currentMonthly = currentMonthly
        }

        public var isEmpty: Bool { ladders.isEmpty }
    }

    public struct Outcome: Sendable {
        public let textChanges: [ChangePlan.ProductTextChange]
        public let groupTextChanges: [ChangePlan.GroupTextChange]
        public let pricePlans: [ChangePlan.PriceChange]
        public let newProducts: [String]

        /// The products and groups whose words go into a new draft.
        public let newDrafts: [String]

        public let blocked: [ChangePlan.Blocked]
        public let skipped: [ChangePlan.Skipped]

        /// Anything the resolver had to say about a price, so `check` and the
        /// plan report the same things.
        public let problems: [Problem]
    }

    /// States a product cannot be edited in.
    ///
    /// App Store Connect refuses a change while it is looking at one, and the
    /// refusal reads as a 409 rather than as anything about review.
    static let statesThatRefuseEdits: Set<String> = [
        "WAITING_FOR_REVIEW", "IN_REVIEW", "PENDING_BINARY_APPROVAL"
    ]

    public static func plan(
        local: ProductCatalog,
        config: ProjectConfig,
        remote: RemoteProducts,
        prices: Prices = Prices()
    ) -> Outcome {
        var textChanges: [ChangePlan.ProductTextChange] = []
        var pricePlans: [ChangePlan.PriceChange] = []
        var newProducts: [String] = []
        var newDrafts: [String] = []
        var blocked: [ChangePlan.Blocked] = []
        var skipped: [ChangePlan.Skipped] = []
        var problems: [Problem] = []

        let onStore = remote.byProductID

        for product in local.sorted {
            guard let match = onStore[product.productID] else {
                newProducts.append(product.productID)
                blocked.append(ChangePlan.Blocked(
                    reason: LocalizedStringResource("""
                    App Store Connect has no in-app purchase called \
                    \(product.productID), and ASCKit never makes one.
                    """, bundle: .here),
                    affects: LocalizedStringResource("\(product.productID)", bundle: .here),
                    cause: .product,
                    parts: [.purchases, .prices]
                ))
                continue
            }

            guard product.status.canPublish else {
                skipped.append(ChangePlan.Skipped(
                    locale: product.productID,
                    reason: LocalizedStringResource("marked \(product.status.rawValue)", bundle: .here)
                ))
                continue
            }

            if let state = match.state, statesThatRefuseEdits.contains(state) {
                let readable = state.lowercased().replacingOccurrences(of: "_", with: " ")
                blocked.append(ChangePlan.Blocked(
                    reason: LocalizedStringResource("""
                    \(product.productID) is \(readable), so App Store Connect \
                    refuses a change to it.
                    """, bundle: .here),
                    affects: LocalizedStringResource("\(product.productID)", bundle: .here),
                    cause: .product,
                    parts: [.purchases, .prices]
                ))
                continue
            }

            // The prices carry on either way. A price does not live in a
            // version, so a product with no draft can still be repriced.
            let wordChanges = words(of: product, against: match, config: config)
            if let stopper = noDraft(for: product.productID, version: match.version),
               wordChanges.isEmpty == false {
                blocked.append(stopper)
            } else {
                textChanges += wordChanges
                if match.version?.needsNewDraft == true, wordChanges.isEmpty == false {
                    newDrafts.append(product.productID)
                }
            }

            let priced = price(of: product, against: match, prices: prices)
            if let plan = priced.plan { pricePlans.append(plan) }
            problems += priced.problems
            blocked += priced.blocked
        }

        let groups = planGroups(local: local, config: config, remote: remote)
        blocked += groups.blocked
        skipped += groups.skipped
        newDrafts += groups.newDrafts

        return Outcome(
            textChanges: textChanges,
            groupTextChanges: groups.changes,
            pricePlans: pricePlans,
            newProducts: newProducts,
            newDrafts: newDrafts,
            blocked: blocked,
            skipped: skipped,
            problems: problems
        )
    }

    /// The words of every subscription group, planned the way a product's are.
    ///
    /// Its own function only because `plan` is at the length SwiftLint allows.
    private static func planGroups(
        local: ProductCatalog,
        config: ProjectConfig,
        remote: RemoteProducts
    ) -> GroupPlan {
        var changes: [ChangePlan.GroupTextChange] = []
        var newDrafts: [String] = []
        var blocked: [ChangePlan.Blocked] = []
        var skipped: [ChangePlan.Skipped] = []
        let onStore = remote.groupsByName

        for group in local.sortedGroups {
            guard let match = onStore[group.referenceName] else {
                blocked.append(ChangePlan.Blocked(
                    reason: LocalizedStringResource("""
                    App Store Connect has no subscription group called \
                    \(group.referenceName), and ASCKit never makes one.
                    """, bundle: .here),
                    affects: LocalizedStringResource("\(group.referenceName)", bundle: .here),
                    cause: .product,
                    parts: [.purchases]
                ))
                continue
            }

            guard group.status.canPublish else {
                skipped.append(ChangePlan.Skipped(
                    locale: group.referenceName,
                    reason: LocalizedStringResource("marked \(group.status.rawValue)", bundle: .here)
                ))
                continue
            }

            let wordChanges = words(of: group, against: match, config: config)
            if let stopper = noDraft(for: group.referenceName, version: match.version),
               wordChanges.isEmpty == false {
                blocked.append(stopper)
            } else {
                changes += wordChanges
                if match.version?.needsNewDraft == true, wordChanges.isEmpty == false {
                    newDrafts.append(group.referenceName)
                }
            }
        }
        return GroupPlan(changes: changes, newDrafts: newDrafts, blocked: blocked, skipped: skipped)
    }

    /// What planning the groups came to.
    private struct GroupPlan {
        let changes: [ChangePlan.GroupTextChange]
        let newDrafts: [String]
        let blocked: [ChangePlan.Blocked]
        let skipped: [ChangePlan.Skipped]
    }

    /// Why the words cannot go, when App Store Connect holds no draft to put
    /// them in and takes no new one.
    ///
    /// Said here, in the plan somebody reads before pressing the button, rather
    /// than as a failure afterwards.
    private static func noDraft(
        for productID: String,
        version: RemoteProductVersion?
    ) -> ChangePlan.Blocked? {
        guard version?.acceptsChanges != true, version?.needsNewDraft != true else { return nil }

        let reason = if let state = version?.state?.rawValue {
            LocalizedStringResource("""
            The words of \(productID) are in a version that is \
            \(state.lowercased().replacingOccurrences(of: "_", with: " ")), so App \
            Store Connect refuses a change to them now.
            """, bundle: .here)
        } else {
            LocalizedStringResource("""
            App Store Connect holds no words for \(productID) yet. Write the first \
            ones there.
            """, bundle: .here)
        }

        return ChangePlan.Blocked(
            reason: reason,
            affects: LocalizedStringResource("\(productID)", bundle: .here),
            cause: .product,
            parts: [.purchases]
        )
    }

    // MARK: - Words

    private static func words(
        of product: Product,
        against remote: RemoteProduct,
        config: ProjectConfig
    ) -> [ChangePlan.ProductTextChange] {
        var changes: [ChangePlan.ProductTextChange] = []

        for locale in config.writtenLocales.sorted() {
            guard let written = product.localizations[locale] else { continue }

            for field in ProductField.allCases {
                guard let newValue = written[field] else { continue }
                let oldValue = remote.localizations[locale]?[field.rawValue]

                // Apple answers with an empty string for a field nobody ever
                // set, so an empty old value is an add rather than a change.
                if let oldValue, oldValue.isEmpty == false {
                    guard oldValue != newValue else { continue }
                    changes.append(.init(
                        productID: product.productID, locale: locale, field: field,
                        action: .change, oldValue: oldValue, newValue: newValue
                    ))
                } else {
                    changes.append(.init(
                        productID: product.productID, locale: locale, field: field,
                        action: .add, oldValue: nil, newValue: newValue
                    ))
                }
            }
        }
        return changes
    }

    private static func words(
        of group: SubscriptionGroup,
        against remote: RemoteSubscriptionGroup,
        config: ProjectConfig
    ) -> [ChangePlan.GroupTextChange] {
        var changes: [ChangePlan.GroupTextChange] = []

        for locale in config.writtenLocales.sorted() {
            guard let written = group.localizations[locale] else { continue }

            for field in GroupField.allCases {
                guard let newValue = written[field] else { continue }
                let oldValue = remote.localizations[locale]?[field.rawValue]

                if let oldValue, oldValue.isEmpty == false {
                    guard oldValue != newValue else { continue }
                    changes.append(.init(
                        group: group.referenceName, locale: locale, field: field,
                        action: .change, oldValue: oldValue, newValue: newValue
                    ))
                } else {
                    // An empty custom app name on both sides is no change.
                    guard newValue.isEmpty == false else { continue }
                    changes.append(.init(
                        group: group.referenceName, locale: locale, field: field,
                        action: .add, oldValue: nil, newValue: newValue
                    ))
                }
            }
        }
        return changes
    }

    // MARK: - Prices

    /// What one product's price worked out to, or why it did not.
    ///
    /// Internal rather than private, so a preview works out a price the same
    /// way a plan does.
    struct Priced {
        var plan: ChangePlan.PriceChange?
        var problems: [Problem] = []
        var blocked: [ChangePlan.Blocked] = []
    }

    static func price(
        of product: Product,
        against remote: RemoteProduct,
        prices: Prices
    ) -> Priced {
        guard let plan = product.price else { return Priced() }
        guard let kind = product.resolvedKind else { return Priced() }

        guard let curve = PriceCurve.named(plan.curve) else {
            // The validator already says this, in words that name the choices.
            // Repeating it here would show it twice in one run.
            return Priced()
        }

        let ladders = prices.ladders[product.productID] ?? [:]
        guard ladders.isEmpty == false else {
            return Priced(blocked: [ChangePlan.Blocked(
                reason: LocalizedStringResource(
                    "\(product.productID) has no prices read from App Store Connect yet.", bundle: .here
                ),
                affects: LocalizedStringResource(
                    "the price of \(product.productID)", bundle: .here
                ),
                cause: .product,
                parts: [.prices]
            )])
        }

        let resolution = PriceResolver.resolve(
            productID: product.productID,
            plan: plan,
            curve: curve,
            anchors: prices.anchors[product.productID] ?? [:],
            ladders: ladders,
            territories: Array(ladders.keys)
        )

        let today = prices.current[product.productID] ?? [:]
        let todayMonthly = prices.currentMonthly[product.productID] ?? [:]

        var rows: [ChangePlan.PriceChange.Row] = []
        var problems: [Problem] = resolution.problems

        for resolved in resolution.prices {
            let yearly = row(from: resolved, today: today[resolved.territory])

            // Only a country that already has an instalment gets one. Giving a
            // country its first would switch the monthly option on somewhere it
            // was never offered, which is a decision rather than a price.
            guard let wasInstalment = todayMonthly[resolved.territory],
                  let wasYearly = today[resolved.territory]
            else {
                rows.append(yearly)
                continue
            }

            guard let point = PriceResolver.instalment(
                matching: resolved.customerPrice,
                wasYearly: wasYearly,
                wasInstalment: wasInstalment,
                in: ladders[resolved.territory] ?? []
            ) else {
                // The year cannot go out on its own. Apple would refuse the
                // whole request, so the country is left out and said out loud
                // rather than quietly taking the rest down with it.
                problems.append(noInstalment(for: product.productID, at: resolved))
                continue
            }

            rows.append(yearly)
            rows.append(instalmentRow(point, was: wasInstalment, like: resolved))
        }

        let unpriced = unpricedCountries(plan: plan, asked: Array(ladders.keys), rows: rows)

        return Priced(
            plan: ChangePlan.PriceChange(
                productID: product.productID,
                kind: kind,
                baseTerritory: plan.baseTerritory,
                baseAmount: plan.baseAmount,
                curveID: curve.id,
                replacesWholeSchedule: kind.priceWriteReplacesEveryTerritory,
                preserveCurrentPrice: kind.isAutoRenewable ? plan.preservesCurrentPrice : nil,
                rows: rows,
                skipped: resolution.skipped,
                unpriced: unpriced
            ),
            problems: problems,
            blocked: blocked(product.productID, unpriced: unpriced)
        )
    }

    /// A country whose year has no instalment that Apple would take.
    private static func noInstalment(for productID: String, at resolved: PriceResolver.Resolved) -> Problem {
        Problem(
            severity: .warning,
            area: .pricing,
            message: LocalizedStringResource("""
            \(productID) cannot be \(resolved.customerPrice.description) in \
            \(resolved.territory): no instalment there works out between a \
            twelfth and an eighth of it.
            """, bundle: .here),
            fix: LocalizedStringResource("""
            Set that country by hand, or leave it out with skip. A year sold \
            with a 12-month commitment needs both prices, and this country's \
            ladder has no instalment Apple would take.
            """, bundle: .here),
            productID: productID,
            territory: resolved.territory,
            kind: .instalmentNotAvailable
        )
    }

    /// One instalment, moved by the same factor the year moved by.
    private static func instalmentRow(
        _ point: PricePoint,
        was: Money,
        like yearly: PriceResolver.Resolved
    ) -> ChangePlan.PriceChange.Row {
        ChangePlan.PriceChange.Row(
            territory: point.territory,
            planType: .monthly,
            currency: point.currency ?? yearly.currency,
            pricePointID: point.id,
            oldAmount: was,
            newAmount: point.customerPrice,
            direction: direction(from: was, to: point.customerPrice),
            source: yearly.source,
            roundedUpBy: "0"
        )
    }

    private static func direction(
        from was: Money?,
        to now: Money
    ) -> ChangePlan.PriceChange.Direction {
        switch was {
        case .none: .new
        case let .some(old) where old < now: .up
        case let .some(old) where old > now: .down
        default: .same
        }
    }

    private static func row(
        from resolved: PriceResolver.Resolved,
        today: Money?
    ) -> ChangePlan.PriceChange.Row {
        ChangePlan.PriceChange.Row(
            territory: resolved.territory,
            planType: .upfront,
            currency: resolved.currency,
            pricePointID: resolved.pricePointID,
            oldAmount: today,
            newAmount: resolved.customerPrice,
            direction: direction(from: today, to: resolved.customerPrice),
            source: resolved.source,
            roundedUpBy: resolved.roundedUpBy
        )
    }
}
