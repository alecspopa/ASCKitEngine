import Foundation

extension ChangePlanFormatter {
    static func priceLines(_ plan: ChangePlan, showingEvery: Bool) -> [String] {
        let changing = plan.pricePlans.filter { $0.changing.isEmpty == false }
        guard changing.isEmpty == false else { return [] }

        var lines = [String(localized: Words.prices)]
        for change in changing {
            lines += onePrice(change, showingEvery: showingEvery)
        }
        return lines + [""] + TextWrapping.lines(PriceResolver.roundingRule) + [""]
    }

    private static func onePrice(
        _ change: ChangePlan.PriceChange,
        showingEvery: Bool
    ) -> [String] {
        var lines = [
            "  \(change.productID), \(change.kind.displayName)",
            "  \(change.curveID) off \(change.baseAmount) in \(change.baseTerritory)"
        ]

        // The two kinds are opposite, and getting them the wrong way round
        // reprices a hundred countries without saying so. So the plan says
        // which one this is, in words, every time.
        if change.replacesWholeSchedule {
            lines += paragraph(String(
                localized: """
                This replaces the whole price schedule. A country not listed here goes back \
                to Apple's equalized price from \(change.baseTerritory).
                """,
                bundle: .module
            ))
        } else {
            lines += paragraph(String(localized: Words.oneRequest))

            if change.rows.contains(where: { $0.planType == .monthly }) {
                lines += paragraph(String(localized: Words.twoPricesPerCountry))
            }
        }

        if let preserving = change.preserveCurrentPrice {
            lines += paragraph(String(localized: preserving
                    ? Words.keepWhatTheyPay
                    : Words.moveToTheNewPrice))
        }

        lines.append("    \(counts(of: change))")
        lines += rows(of: change, showingEvery: showingEvery)

        if change.skipped.isEmpty == false {
            let names = change.skipped.map(\.territory).formatted(.list(type: .and, width: .narrow))
            lines.append("    " + String(localized: "Left out: \(names)", bundle: .module))
        }
        return lines
    }

    /// One paragraph, wrapped where a terminal can read it and indented to sit
    /// under the product it is about.
    ///
    /// Wrapped here rather than written wrapped, because a translation is a
    /// different length and a sentence broken into four literals is four
    /// things to translate and one thing to get wrong.
    static func paragraph(_ text: String, indent: String = "    ") -> [String] {
        TextWrapping.lines(text, at: 76 - indent.count).map { indent + $0 }
    }

    /// Written without verbs, so no number needs a plural to agree with, and a
    /// person scanning the line reads four numbers rather than a sentence.
    private static func counts(of change: ChangePlan.PriceChange) -> String {
        let fresh = change.rows.count { $0.direction == .new }
        var parts = [
            String(localized: "\(change.rises.count) up", bundle: .module),
            String(localized: "\(change.falls.count) down", bundle: .module)
        ]
        if fresh > 0 { parts.append(String(localized: "\(fresh) new", bundle: .module)) }
        parts.append(String(localized: "\(change.unchanged.count) unchanged", bundle: .module))

        return String(
            localized: """
            \(change.rows.count) countries: \
            \(parts.formatted(.list(type: .and, width: .narrow))).
            """,
            bundle: .module
        )
    }

    /// The rows that change, biggest move first, because that is the order
    /// somebody wants to read them in.
    private static func rows(
        of change: ChangePlan.PriceChange,
        showingEvery: Bool
    ) -> [String] {
        let ordered = change.changing.sorted { left, right in
            if left.direction != right.direction {
                return left.direction == .up
            }
            return left.territory < right.territory
        }

        let shown = showingEvery ? ordered : Array(ordered.prefix(pricesShownByDefault))
        var lines = shown.map { "      \(describe($0))" }

        let hidden = ordered.count - shown.count
        if hidden > 0 {
            lines.append("      " + String(
                localized: "...and \(hidden) more. asckit diff --prices shows every line.",
                bundle: .module
            ))
        }
        return lines
    }

    private static func describe(_ row: ChangePlan.PriceChange.Row) -> String {
        let from = row.oldAmount?.formatted(currency: row.shownCurrency) ?? String(localized: Words.none)
        let now = row.newAmount.formatted(currency: row.shownCurrency)
        var text = String(localized: """
        \(row.territory)  \(row.planType.displayName)  \
        \(from) to \(now)  \(row.direction.rawValue)
        """, bundle: .module)

        switch row.source {
        case .base: text += "  \(String(localized: Words.theBasePrice))"
        case let .curve(band): text += band.map { "  \($0)" } ?? ""
        case .overrideAmount, .overridePricePoint: text += "  \(String(localized: Words.setByHand))"
        }
        if row.roundedUpBy.isPositive { text += "  \(String(localized: Words.roundedUp))" }
        return text
    }
}
