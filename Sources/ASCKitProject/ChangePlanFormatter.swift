import Foundation

/// Turns a plan into something a person reads before deciding to publish.
///
/// In the library rather than in the command, so the wording is tested and the
/// app's publish sheet can say the same things.
public enum ChangePlanFormatter {
    /// How many price rows to print before saying how many are left.
    ///
    /// Nobody reads 177 lines, and the ones that matter are at the top because
    /// the plan sorts them there. The counts come before the rows for the same
    /// reason.
    public static let pricesShownByDefault = 12

    /// The headings and the standalone sentences, each named once.
    private enum Words {
        static let nothingToChange = LocalizedStringResource(
            "Nothing to change. App Store Connect already matches these files.", bundle: .here
        )
        static let noChanges = LocalizedStringResource("No changes.", bundle: .here)
        static let versionClosed = LocalizedStringResource(
            "Version status does not allow any more updates.", bundle: .here
        )
        static let cannotBeDone = LocalizedStringResource("Cannot be done now:", bundle: .here)
        static let text = LocalizedStringResource("Text:", bundle: .here)
        static let screenshots = LocalizedStringResource("Screenshots:", bundle: .here)
        static let previews = LocalizedStringResource("App previews:", bundle: .here)
        static let creative = LocalizedStringResource("Header and search results:", bundle: .here)
        static let purchases = LocalizedStringResource("In-app purchases:", bundle: .here)
        static let groups = LocalizedStringResource("Subscription groups:", bundle: .here)
        static let prices = LocalizedStringResource("Prices:", bundle: .here)
        static let leftOut = LocalizedStringResource("Left out:", bundle: .here)
        static let noChange = LocalizedStringResource("no change", bundle: .here)
        static let theBasePrice = LocalizedStringResource("the base price", bundle: .here)
        static let setByHand = LocalizedStringResource("set by hand", bundle: .here)
        static let roundedUp = LocalizedStringResource("rounded up", bundle: .here)
        static let none = LocalizedStringResource("none", bundle: .here)
        static let keepWhatTheyPay = LocalizedStringResource(
            "People who already subscribe keep what they pay.", bundle: .here
        )
        static let moveToTheNewPrice = LocalizedStringResource("""
        People who already subscribe move to the new price. On a rise Apple asks them, \
        and cancels the ones who do not answer.
        """, bundle: .here)
        static let oneRequest = LocalizedStringResource("""
        Every country goes in one request. A subscription has no price schedule. \
        It takes an update that carries every country instead. ASCKit sends them all, \
        whether or not they change. Apple does not say whether an update replaces \
        the set or adds to it.
        """, bundle: .here)
        static let twoPricesPerCountry = LocalizedStringResource("""
        Two prices per country: the year, and one month of it on a 12-month commitment. \
        Both move by the same factor. Twelve instalments have to come to the price \
        of the year or more. They also have to come to one and a half times it or less.
        """, bundle: .here)
    }

    public static func lines(
        for plan: ChangePlan,
        showingEveryPrice: Bool = false
    ) -> [String] {
        var lines: [String] = []

        lines += blockedLines(plan)
        lines += missingLocaleLines(plan)
        lines += textLines(plan)
        lines += screenshotLines(plan)
        lines += previewLines(plan)
        lines += creativeLines(plan)
        lines += productTextLines(plan)
        lines += priceLines(plan, showingEvery: showingEveryPrice)
        lines += skippedLines(plan)

        if lines.isEmpty {
            lines.append(String(localized: Words.nothingToChange))
        }
        return lines
    }

    public static func summary(_ plan: ChangePlan) -> String {
        guard plan.isEmpty == false else { return String(localized: Words.noChanges) }

        var parts: [String] = []
        if plan.textChanges.isEmpty == false {
            parts.append(String(localized: "\(plan.textChanges.count) fields", bundle: .module))
        }

        let sets = plan.screenshotPlans.filter(\.changesAnything).count
        if sets > 0 {
            parts.append(String(localized: "\(sets) screenshot sets", bundle: .module))
        }

        let previews = plan.previewPlans.filter(\.changesAnything).count
        if previews > 0 {
            parts.append(String(localized: "\(previews) app preview sets", bundle: .module))
        }

        let art = plan.creativePlans.filter(\.changesAnything).count
        if art > 0 {
            parts.append(String(localized: "\(art) header and search results assets", bundle: .module))
        }

        if plan.productTextChanges.isEmpty == false {
            parts.append(String(
                localized: "\(plan.productTextChanges.count) in-app purchase fields", bundle: .module
            ))
        }

        if plan.groupTextChanges.isEmpty == false {
            parts.append(String(
                localized: "\(plan.groupTextChanges.count) subscription group fields", bundle: .module
            ))
        }

        let priced = plan.pricePlans.filter { $0.changing.isEmpty == false }
        if priced.isEmpty == false {
            let rows = priced.reduce(0) { $0 + $1.changing.count }
            parts.append(String(
                localized: "\(rows) prices in \(priced.count) products", bundle: .module
            ))
        }

        var text = String(
            localized: "Would change \(parts.formatted(.list(type: .and))).", bundle: .module
        )
        if let blocked = blockedSentence(plan) {
            text += " \(blocked)"
        }
        return text
    }

    /// What stops the push, in one sentence, or nil when nothing does.
    ///
    /// The version's state is named because it is the one a person can do
    /// nothing about from these files, and the count would tell them nothing.
    private static func blockedSentence(_ plan: ChangePlan) -> String? {
        guard plan.blocked.isEmpty == false else { return nil }

        if plan.blocked.allSatisfy({ $0.cause == .versionStatus }) {
            return String(localized: Words.versionClosed)
        }
        return String(
            localized: "\(plan.blocked.count) things cannot be done in this state.", bundle: .module
        )
    }

    /// What one part of a push would change, at a glance.
    ///
    /// Nil when that part would change nothing, so the row beside it can say
    /// that in its own words rather than showing a zero.
    ///
    /// Written without verbs, the way `counts(of:)` is, so no number needs a
    /// plural to agree with and a person reads two numbers rather than a
    /// sentence.
    public static func count(of part: PublishPart, in plan: ChangePlan) -> String? {
        guard plan.changes(part) else { return nil }

        switch part {
        case .appInformation:
            return String(localized: """
            \(plan.textChanges.count) fields, \(plan.changedTextLocales) languages
            """, bundle: .module)
        case .purchases:
            guard plan.groupTextChanges.isEmpty == false else {
                return String(localized: """
                \(plan.productTextChanges.count) fields, \(plan.changedTextProducts) purchases
                """, bundle: .module)
            }
            guard plan.productTextChanges.isEmpty == false else {
                return String(localized: """
                \(plan.groupTextChanges.count) fields, \(plan.changedTextGroups) groups
                """, bundle: .module)
            }
            return String(localized: """
            \(plan.productTextChanges.count + plan.groupTextChanges.count) fields, \
            \(plan.changedTextProducts) purchases, \(plan.changedTextGroups) groups
            """, bundle: .module)
        case .prices:
            return String(localized: """
            \(plan.changedPriceRows) prices, \(plan.changedPricedProducts) products
            """, bundle: .module)
        case .screenshots:
            // One part writes all three, so the count names each one that moves.
            var pieces = screenshotCount(plan).map { [$0] } ?? []
            let previewSets = plan.previewPlans.count(where: \.changesAnything)
            if previewSets > 0 {
                pieces.append(String(localized: "\(previewSets) preview sets", bundle: .module))
            }
            if plan.creativePlans.contains(where: \.changesAnything) {
                pieces.append(String(localized: "header and search results art", bundle: .module))
            }
            return pieces.formatted(.list(type: .and))
        case .productPageOptimization:
            return nil
        }
    }

    private static func screenshotCount(_ plan: ChangePlan) -> String? {
        guard plan.changedScreenshotSets > 0 else { return nil }
        // A set that only empties would otherwise read "2 sets, 0 images",
        // which reads as a fault rather than as a removal.
        if plan.imagesToAdd > 0 {
            return String(localized: """
            \(plan.changedScreenshotSets) sets, \(plan.imagesToAdd) images
            """, bundle: .module)
        }
        if plan.imagesToRemove > 0 {
            return String(localized: """
            \(plan.changedScreenshotSets) sets, removing \(plan.imagesToRemove) images
            """, bundle: .module)
        }
        return String(localized: "\(plan.changedScreenshotSets) sets in a new order", bundle: .module)
    }

    // MARK: - Sections

    private static func blockedLines(_ plan: ChangePlan, only part: PublishPart? = nil) -> [String] {
        let blocked = part.map { plan.blocked($0) } ?? plan.blocked
        guard blocked.isEmpty == false else { return [] }
        let reasons = blocked.map {
            "  " + String(localized: "\($0.reason) Affects \($0.affects).", bundle: .module)
        }
        return [String(localized: Words.cannotBeDone)] + reasons + [""]
    }

    private static func missingLocaleLines(_ plan: ChangePlan) -> [String] {
        guard plan.missingLocales.isEmpty == false else { return [] }
        return [
            String(
                localized: """
                App Store Connect has no page in \
                \(plan.missingLocales.formatted(.list(type: .and, width: .narrow))), \
                so nothing is written in those. Make the language there and read again, \
                or ignore it with asckit ignore.
                """,
                bundle: .module
            ),
            ""
        ]
    }

    private static func textLines(_ plan: ChangePlan) -> [String] {
        guard plan.textChanges.isEmpty == false else { return [] }
        var lines = [String(localized: Words.text)]

        for locale in orderedLocales(of: plan.textChanges) {
            lines.append("  \(locale)")
            for change in plan.textChanges.filter({ $0.locale == locale }) {
                lines.append("    \(change.field.rawValue)")
                if let oldValue = change.oldValue {
                    lines.append("      was:  \(shorten(oldValue))")
                }
                lines.append("      \(change.oldValue == nil ? "new:" : "now: ") \(shorten(change.newValue))")
            }
        }
        return lines + [""]
    }

    private static func screenshotLines(_ plan: ChangePlan) -> [String] {
        let changing = plan.screenshotPlans.filter(\.changesAnything)
        guard changing.isEmpty == false else { return [] }

        var lines = [String(localized: Words.screenshots)]
        for item in changing {
            let words = describeOrderOnly(item.library) ?? describe(item.action)
            lines.append("  \(item.locale), \(item.deviceClass.displayName): \(words)")
        }
        return lines + [""]
    }

    /// Only the in-app purchase words, for the command that writes only those.
    ///
    /// A command that shows a person everything a push *could* do, and then
    /// does one part of it, teaches them to skim.
    public static func productWordLines(for plan: ChangePlan) -> [String] {
        blockedLines(plan, only: .purchases) + productTextLines(plan)
    }

    /// Only the prices, for the same reason.
    public static func priceLines(
        for plan: ChangePlan,
        showingEveryPrice: Bool = false
    ) -> [String] {
        blockedLines(plan, only: .prices) + priceLines(plan, showingEvery: showingEveryPrice)
    }

    private static func productTextLines(_ plan: ChangePlan) -> [String] {
        purchaseTextLines(plan) + groupTextLines(plan) + newDraftLines(plan)
    }

    /// Said before the push, because the new draft stays in App Store Connect
    /// and has to go to review.
    private static func newDraftLines(_ plan: ChangePlan) -> [String] {
        guard plan.newDrafts.isEmpty == false else { return [] }
        return paragraph(String(
            localized: """
            App Review is done with the words of \
            \(plan.newDrafts.formatted(.list(type: .and))). The push makes a new draft \
            of them, with a copy of the words there now, and changes the copy. \
            Send the draft to review in App Store Connect.
            """,
            bundle: .module
        ), indent: "  ") + [""]
    }

    private static func groupTextLines(_ plan: ChangePlan) -> [String] {
        guard plan.groupTextChanges.isEmpty == false else { return [] }
        var lines = [String(localized: Words.groups)]

        for change in plan.groupTextChanges {
            lines.append("  \(change.group), \(change.locale)")
            lines.append("    \(change.field.rawValue)")
            if let oldValue = change.oldValue {
                lines.append("      was:  \(shorten(oldValue))")
            }
            let label = change.oldValue == nil ? "new:" : "now: "
            lines.append("      \(label) \(shorten(change.newValue))")
        }
        return lines + [""]
    }

    private static func purchaseTextLines(_ plan: ChangePlan) -> [String] {
        guard plan.productTextChanges.isEmpty == false else { return [] }
        var lines = [String(localized: Words.purchases)]

        for change in plan.productTextChanges {
            lines.append("  \(change.productID), \(change.locale)")
            lines.append("    \(change.field.rawValue)")
            if let oldValue = change.oldValue {
                lines.append("      was:  \(shorten(oldValue))")
            }
            let label = change.oldValue == nil ? "new:" : "now: "
            lines.append("      \(label) \(shorten(change.newValue))")
        }
        return lines + [""]
    }

    // MARK: - Prices

    private static func priceLines(_ plan: ChangePlan, showingEvery: Bool) -> [String] {
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
    private static func paragraph(_ text: String, indent: String = "    ") -> [String] {
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

    private static func skippedLines(_ plan: ChangePlan) -> [String] {
        guard plan.skipped.isEmpty == false else { return [] }
        return [String(localized: Words.leftOut)]
            + plan.skipped.map { "  \($0.locale), \(String(localized: $0.reason))" }
            + [""]
    }

    // MARK: - Wording

    private static func describe(_ action: ChangePlan.ScreenshotPlan.Action) -> String {
        switch action {
        case .unchanged:
            String(localized: Words.noChange)
        case let .replace(removing, adding) where removing == 0:
            String(localized: "add \(adding) images", bundle: .module)
        case let .replace(removing, 0):
            String(localized: "remove all \(removing) images", bundle: .module)
        case let .replace(removing, adding):
            String(localized: "remove \(removing) images, then add \(adding) images", bundle: .module)
        }
    }

    /// Long values are for reading, not for auditing, so a description does not
    /// need all 4000 characters of itself on screen.
    private static func shorten(_ value: String, to limit: Int = 72) -> String {
        let oneLine = value.replacingOccurrences(of: "\n", with: " ")
        guard oneLine.count > limit else { return oneLine }
        return "\(oneLine.prefix(limit - 1))…"
    }

    private static func orderedLocales(of changes: [ChangePlan.TextChange]) -> [String] {
        var seen: Set<String> = []
        return changes.map(\.locale).filter { seen.insert($0).inserted }
    }
}

// MARK: - The App Asset Library

private extension ChangePlanFormatter {
    static func previewLines(_ plan: ChangePlan) -> [String] {
        let changing = plan.previewPlans.filter(\.changesAnything)
        guard changing.isEmpty == false else { return [] }

        var lines = [String(localized: Words.previews)]
        for item in changing {
            let words = describeOrderOnly(item.library) ?? describeVideos(item.action)
            lines.append("  \(item.locale), \(item.deviceClass.displayName): \(words)")
        }
        return lines + [""]
    }

    static func creativeLines(_ plan: ChangePlan) -> [String] {
        let changing = plan.creativePlans.filter(\.changesAnything)
        guard changing.isEmpty == false else { return [] }

        var lines = [String(localized: Words.creative)]
        for item in changing {
            let role = item.role == .header
                ? String(localized: "header", bundle: .module)
                : String(localized: "search results", bundle: .module)
            let words = if let file = item.file, item.usesHeader {
                String(localized: "show the header, \(file.fileName)", bundle: .module)
            } else if let file = item.file {
                String(localized: "put up \(file.fileName)", bundle: .module)
            } else {
                String(localized: "take it off", bundle: .module)
            }
            lines.append("  \(item.locale), \(role): \(words)")
        }
        return lines + [""]
    }

    /// A slot of the library that keeps every file it has, and changes only
    /// their order or a poster frame. Nil when a file comes or goes.
    static func describeOrderOnly(_ slot: LibrarySlot) -> String? {
        guard slot.toRemove.isEmpty, slot.placementsToAdd == 0 else { return nil }
        return slot.posterFrames.isEmpty
            ? String(localized: "change the order", bundle: .module)
            : String(localized: "change the poster frame", bundle: .module)
    }

    static func describeVideos(_ action: ChangePlan.ScreenshotPlan.Action) -> String {
        switch action {
        case .unchanged:
            String(localized: Words.noChange)
        case let .replace(removing, adding) where removing == 0:
            String(localized: "add \(adding) videos", bundle: .module)
        case let .replace(removing, 0):
            String(localized: "remove all \(removing) videos", bundle: .module)
        case let .replace(removing, adding):
            String(localized: "remove \(removing) videos, then add \(adding) videos", bundle: .module)
        }
    }
}
