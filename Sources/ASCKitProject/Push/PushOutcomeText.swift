import ASCKitAPI
import Foundation

/// What a push did, in the words the window puts on screen.
///
/// In the library rather than in the window, for the reason
/// `ChangePlanFormatter` is: the wording is tested, and it reads the outcome
/// and nothing else.
///
/// The shape is the shape `ChangePlanFormatter` uses for the plan: a heading,
/// then one indented line per thing. A push touches every language at once, so
/// a single comma-separated line is too long to read.
public enum PushOutcomeText {
    /// The words the report is built from, each named once.
    ///
    /// A heading is written in several reports, and a sentence written twice
    /// is a sentence to translate twice and get different both times.
    private enum Words {
        static let written = LocalizedStringResource("Written:", bundle: .here)
        static let leftAlone = LocalizedStringResource("Left alone, already there:", bundle: .here)
        static let leftListed = LocalizedStringResource("Left alone, already listed:", bundle: .here)
        static let added = LocalizedStringResource("Added:", bundle: .here)
        static let informationWritten = LocalizedStringResource("App information file written for:", bundle: .here)
        static let cleared = LocalizedStringResource("Written again with no alpha channel:", bundle: .here)
        static let leftAsTheyWere = LocalizedStringResource("Left as they were:", bundle: .here)
        static let refused = LocalizedStringResource("Refused:", bundle: .here)
        static let refusedInThisState = LocalizedStringResource("Refused in this state:", bundle: .here)
        static let failed = LocalizedStringResource("Failed:", bundle: .here)
        static let archived = LocalizedStringResource(
            "Archived in the library, because nothing shows them any more:", bundle: .here
        )
        static let overwritten = LocalizedStringResource("Overwritten:", bundle: .here)
        static let filled = LocalizedStringResource("Filled from App Store Connect:", bundle: .here)

        static let nothingToWrite = LocalizedStringResource("Nothing to write.", bundle: .here)
        static let nothingToAdd = LocalizedStringResource("Nothing to add.", bundle: .here)
        static let nothingToClear = LocalizedStringResource("Nothing to clear.", bundle: .here)
        static let nothingToUpload = LocalizedStringResource("Nothing to upload.", bundle: .here)
        static let nothingToFill = LocalizedStringResource("Nothing to fill.", bundle: .here)
        static let originalsInTrash = LocalizedStringResource(
            "The files as they arrived are in the Trash.", bundle: .here
        )
        static let fromSibling = LocalizedStringResource(
            "Screenshots copied from another language, as copiesScreenshotsFrom says:", bundle: .here
        )
        static let olderInTrash = LocalizedStringResource(
            "The files that were there are in the Trash.", bundle: .here
        )
        static let writeAgain = LocalizedStringResource(
            "Read the prices again and write once more. Only what is still wrong goes out.", bundle: .here
        )
    }

    public static func describe(_ outcome: SnapshotWriter.Outcome) -> String {
        let text = join([
            section(Words.written, outcome.written),
            section(Words.leftAlone, outcome.skipped)
        ])
        return text.isEmpty ? String(localized: Words.nothingToWrite) : text
    }

    /// What making a new version folder put in it.
    public static func describe(_ outcome: VersionSeed.Outcome, versionsPath: String) -> String {
        let version = outcome.folder.lastPathComponent
        let made = String(localized: "Made \(versionsPath)/\(version) from App Store Connect.", bundle: .module)
        let slots = { (slots: [VersionSeed.Slot]) in
            slots.map { "\($0.locale), \($0.deviceClass.displayName)" }
        }
        let copied = LocalizedStringResource("Screenshots copied from an older version folder:", bundle: .here)
        let missing = LocalizedStringResource("""
        Screenshots with no file here. Put the files in these sets \
        before you publish, or App Store Connect loses them:
        """, bundle: .here)

        return join([
            [made],
            section(Words.informationWritten, outcome.written),
            section(copied, slots(outcome.copied)),
            section(Words.fromSibling, lines(outcome.fromSibling)),
            section(missing, slots(outcome.missing))
        ])
    }

    /// The version folders that went to the Trash because App Store Connect
    /// never released those versions. Empty when none went.
    public static func describeTrashedVersions(_ names: [String], versionsPath: String) -> String {
        let trashed = LocalizedStringResource(
            "Moved to the Trash, because App Store Connect never released these versions:", bundle: .here
        )
        return join([section(trashed, names.map { "\(versionsPath)/\($0)" })])
    }

    /// What the copies that `copiesScreenshotsFrom` names did, after pictures
    /// arrived in the language they come from. Empty when none was made.
    ///
    /// The Trash is said out loud, because nobody pressed anything to send
    /// those files there.
    public static func describe(_ copies: [SiblingScreenshots.Remembered]) -> String {
        var sections = [section(Words.fromSibling, lines(copies))]
        if copies.contains(where: { $0.trashed > 0 }) {
            sections.append([String(localized: Words.olderInTrash)])
        }
        return join(sections)
    }

    private static func lines(_ copies: [SiblingScreenshots.Remembered]) -> [String] {
        copies.map {
            String(
                localized: "\($0.locale), \($0.deviceClass.displayName), from \($0.from)",
                bundle: .module
            )
        }
    }

    /// What filling the empty fields did. One line per language, naming the
    /// fields, because the words arrived without anybody typing them and the
    /// only way to find them is to be told where they went.
    public static func describe(_ outcome: SnapshotWriter.FillOutcome) -> String {
        let lines = outcome.locales.map { locale in
            let fields = (outcome.filled[locale] ?? []).map(\.displayName)
            return "\(locale): \(fields.formatted(.list(type: .and, width: .narrow)))"
        }

        let text = join([section(Words.filled, lines)])
        return text.isEmpty ? String(localized: Words.nothingToFill) : text
    }

    public static func describe(_ adoption: LocaleAdoption.Outcome) -> String {
        let text = join([
            section(Words.added, adoption.added),
            section(Words.informationWritten, adoption.written),
            section(Words.leftAlone, adoption.left)
        ])
        return text.isEmpty ? String(localized: Words.nothingToAdd) : text
    }

    public static func describe(_ adoption: DeviceClassAdoption.Outcome) -> String {
        let text = join([
            section(Words.added, adoption.added),
            section(Words.leftListed, adoption.left)
        ])
        return text.isEmpty ? String(localized: Words.nothingToAdd) : text
    }

    /// What clearing the alpha channels did.
    ///
    /// The Trash line is said out loud rather than left out, because this
    /// changes the pixels of a file somebody put there and the copy as it
    /// arrived is the only way back.
    public static func describe(_ outcome: AlphaRemoval.Outcome) -> String {
        let failures = outcome.failed.map { "\($0.fileName): \($0.reason)" }
        var sections = [
            section(Words.cleared, outcome.cleared),
            section(Words.leftAsTheyWere, failures)
        ]
        if outcome.trashed.isEmpty == false {
            sections.append([String(localized: Words.originalsInTrash)])
        }

        let text = join(sections)
        return text.isEmpty ? String(localized: Words.nothingToClear) : text
    }

    /// What taking the store's in-app purchases into files did.
    ///
    /// A refusal carries its own reason, so those get a line each rather than a
    /// heading and a list.
    public static func describe(_ outcome: ProductSnapshot.Outcome) -> String {
        let refusals = outcome.refused.map {
            String(localized: "Skipped \($0.productID). \($0.reason)", bundle: .module)
        }
        let text = join([
            section(Words.written, outcome.written + outcome.writtenGroups.map { "groups/\($0)" }),
            section(Words.leftAlone, outcome.left),
            refusals
        ])
        return text.isEmpty ? String(localized: Words.nothingToWrite) : text
    }

    /// What following the group names of App Store Connect did.
    ///
    /// The Trash is said out loud, because a group file that went may hold a
    /// translation somebody wants back.
    public static func describe(_ followed: SubscriptionGroupDrift.Followed) -> String {
        let renamed = LocalizedStringResource(
            "Renamed to the name App Store Connect uses:", bundle: .here
        )
        let trashed = LocalizedStringResource(
            "Moved to the Trash, because App Store Connect has no such group:", bundle: .here
        )

        let text = join([
            section(renamed, followed.renamed.map {
                String(localized: "groups/\($0.from) is now groups/\($0.to)", bundle: .module)
            }),
            section(trashed, followed.trashed.map { "groups/\($0)" }),
            section(Words.written, followed.written.map { "groups/\($0)" })
        ])
        return text.isEmpty ? String(localized: Words.nothingToWrite) : text
    }

    /// What the push did, and where the record of it went.
    ///
    /// The record is said out loud rather than filed silently, because the
    /// history folder is part of the project and a person should know it grew.
    static func describe(_ outcome: PushSession.Outcome<some Any>, _ what: String) -> String {
        guard let failure = outcome.receiptFailure else {
            guard let receipt = outcome.receiptURL else { return what }
            let line = String(localized: "Recorded in \(receipt.lastPathComponent)", bundle: .module)
            return "\(what)\n\n\(line)"
        }
        let line = String(
            localized: "The push went. The record of it could not be written: \(failure)",
            bundle: .module
        )
        return "\(what)\n\n\(line)"
    }

    public static func describe(_ outcome: PushSession.Outcome<TextPusher.Result>) -> String {
        describe(outcome, describe(outcome.result))
    }

    public static func describe(_ outcome: PushSession.Outcome<ScreenshotPusher.Result>) -> String {
        describe(outcome, describe(outcome.result))
    }

    public static func describe(_ outcome: PushSession.Outcome<ProductPusher.TextResult>) -> String {
        describe(outcome, describe(outcome.result))
    }

    public static func describe(_ outcome: PushSession.Outcome<ProductPusher.PriceResult>) -> String {
        describe(outcome, describe(outcome.result))
    }

    /// Several pushes in one press, each under the name of the part that made
    /// it.
    ///
    /// One button writes up to four things, so a report that did not name them
    /// would leave a person guessing which half of it failed. The heading is
    /// the part's own `heading`, so the report and the checkbox that caused it
    /// say the same word.
    ///
    /// Each part's report goes in whole, receipt line and all, so nothing is
    /// lost by joining them.
    public static func joined(_ parts: [(part: PublishPart, outcome: String)]) -> String {
        let sections = parts.map { ["\(String(localized: $0.part.heading)):"] + indent($0.outcome) }
        let text = join(sections)
        return text.isEmpty ? String(localized: Words.nothingToWrite) : text
    }

    /// Two spaces on every line that has something on it. A blank line stays
    /// blank rather than becoming two spaces, because a person selects this
    /// text and pastes it somewhere.
    private static func indent(_ text: String) -> [String] {
        text.split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.isEmpty ? "" : "  \($0)" }
    }

    public static func describe(_ result: ProductPusher.TextResult) -> String {
        let failures = result.failed.map { failure -> String in
            let what = failure.what.isEmpty ? "" : ", \(failure.what)"
            return "\(failure.productID)\(what): \(failure.reason)"
        }

        let text = join([
            section(Words.written, result.written),
            section(Words.refused, failures)
        ])
        return text.isEmpty ? String(localized: Words.nothingToWrite) : text
    }

    /// What a price push did, and where to find each half of it.
    ///
    /// A cut takes effect at once and replaces the row it changes. A rise
    /// becomes a scheduled price change dated today, and App Store Connect
    /// shows those on a page of their own. Somebody who has just lowered three
    /// hundred countries and raised two finds a page listing two, and without
    /// this reads that as a failure.
    public static func describe(_ result: ProductPusher.PriceResult) -> String {
        let failures = result.failed.map { failure -> String in
            let what = failure.what.isEmpty ? "" : ", \(failure.what)"
            return "\(failure.productID)\(what): \(failure.reason)"
        }

        var lines: [[String]] = []
        if result.written.isEmpty == false {
            let heading = String(localized: "Written: \(result.written.count) prices.", bundle: .module)
            lines.append([heading] + whereToLook(result))
        }
        if failures.isEmpty == false {
            lines.append([String(localized: Words.refused)] + failures.map { "  \($0)" })
            lines.append([String(localized: Words.writeAgain)])
        }

        let text = join(lines)
        return text.isEmpty ? String(localized: Words.nothingToWrite) : text
    }

    private static func whereToLook(_ result: ProductPusher.PriceResult) -> [String] {
        let rises = result.written.filter { written in
            guard let from = written.from,
                  let was = Money(string: from),
                  let now = Money(string: written.to)
            else { return false }
            return now > was
        }
        let falls = result.written.count - rises.count

        var lines: [String] = []
        if falls > 0 {
            lines.append("  " + String(localized: """
            \(falls) prices went down. A cut takes effect now, so look for those in \
            the subscription's own price list.
            """, bundle: .module))
        }
        if rises.isEmpty == false {
            lines.append("  " + String(localized: """
            \(rises.count) prices went up. A rise becomes a scheduled price change \
            dated today, and that page holds nothing else. People who already subscribe \
            stay on the old price.
            """, bundle: .module))
        }
        return lines
    }

    public static func describe(_ result: TextPusher.Result) -> String {
        let refusals = result.refused.map { refusal -> String in
            guard result.written.contains(refusal.locale) else {
                return "\(refusal.locale), \(refusal.field.rawValue)."
            }
            return String(
                localized: "\(refusal.locale), \(refusal.field.rawValue). The rest of \(refusal.locale) went.",
                bundle: .module
            )
        }
        let failures = result.failed.map { "\($0.locale): \($0.message)" }

        let text = join([
            section(Words.written, result.written),
            section(Words.refusedInThisState, refusals),
            section(Words.failed, failures)
        ])
        return text.isEmpty ? String(localized: Words.nothingToWrite) : text
    }

    public static func describe(_ result: ScreenshotPusher.Result) -> String {
        let uploaded = byLocale(result.uploaded).map { "\($0.locale): \($0.rest.joined(separator: ", "))" }
        let failures = result.failed.map { "\($0.locale), \($0.deviceClassID): \($0.message)" }

        let archived = result.archived.map { $0.referenceName ?? $0.fileName ?? $0.id }

        let text = join([
            section(Words.overwritten, uploaded),
            section(Words.archived, archived),
            section(Words.failed, failures)
        ])
        return text.isEmpty ? String(localized: Words.nothingToUpload) : text
    }

    // MARK: - Shape

    private static func section(_ heading: LocalizedStringResource, _ items: [String]) -> [String] {
        items.isEmpty ? [] : [String(localized: heading)] + items.map { "  \($0)" }
    }

    private static func join(_ sections: [[String]]) -> String {
        let kept = sections.filter { $0.isEmpty == false }
        return Array(kept.joined(separator: [""])).joined(separator: "\n")
    }

    /// Screenshot sets are named `locale|deviceClass`, and a push does several
    /// device classes of one language. One line per language reads better than
    /// one line per set.
    private static func byLocale(_ ids: [String]) -> [(locale: String, rest: [String])] {
        var order: [String] = []
        var rest: [String: [String]] = [:]

        for id in ids {
            let parts = id.split(separator: "|", maxSplits: 1).map(String.init)
            let locale = parts.first ?? id
            if rest[locale] == nil { order.append(locale) }
            rest[locale, default: []].append(parts.count > 1 ? parts[1] : "")
        }
        return order.map { (locale: $0, rest: rest[$0] ?? []) }
    }
}
