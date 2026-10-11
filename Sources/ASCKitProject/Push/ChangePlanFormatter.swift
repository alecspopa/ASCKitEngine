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
    enum Words {
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
        lines += unusedLines(plan)
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

        let sets = plan.screenshotPlans.count(where: \.changesAnything)
        if sets > 0 {
            parts.append(String(localized: "\(sets) screenshot sets", bundle: .module))
        }

        let previews = plan.previewPlans.count(where: \.changesAnything)
        if previews > 0 {
            parts.append(String(localized: "\(previews) app preview sets", bundle: .module))
        }

        let art = plan.creativePlans.count(where: \.changesAnything)
        if art > 0 {
            parts.append(String(localized: "\(art) header and search results assets", bundle: .module))
        }

        parts += unusedCount(plan).map { [$0] } ?? []

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
            pieces += unusedCount(plan).map { [$0] } ?? []
            return pieces.formatted(.list(type: .and))
        case .productPageOptimization, .customProductPages:
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
            lines.append("  \(item.locale), \(item.deviceClass.displayName): \(withReason(words, isListed: item.isListed))")
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
