import ASCKitAPI
import Foundation

/// Writes the listing text to App Store Connect, one language at a time.
///
/// Works from a plan rather than from the files, so what is written is exactly
/// what was shown before anyone agreed to it.
public struct TextPusher: Sendable {
    public struct Result: Sendable {
        public var written: [String] = []
        public var failed: [Failure] = []

        /// Fields App Store Connect refused in a state that accepted the rest.
        /// What's new on a first version is the usual one.
        public var refused: [Refusal] = []

        public var isCompleteSuccess: Bool { failed.isEmpty && refused.isEmpty }
    }

    public struct Failure: Sendable {
        public let locale: String
        public let message: String
    }

    public struct Refusal: Sendable, Hashable {
        public let locale: String
        public let field: MetadataField
        public let reason: String
    }

    /// The fields named in a refusal, from either place App Store Connect puts
    /// them: the source pointer, and the wording of the detail.
    static func refusedFields(in error: any Error) -> Set<MetadataField> {
        guard let ascError = error as? ASCError, case .conflict = ascError else { return [] }

        var fields: Set<MetadataField> = []
        for detail in ascError.details {
            if let pointer = detail.pointer,
               let name = pointer.split(separator: "/").last,
               let field = MetadataField(rawValue: String(name)) {
                fields.insert(field)
            }
            if let text = detail.detail ?? detail.title {
                for field in MetadataField.allCases where text.contains("'\(field.rawValue)'") {
                    fields.insert(field)
                }
            }
        }
        return fields
    }

    private let client: ASCClient

    /// Reachable only from inside the package, so every push goes through
    /// `PushSession` and leaves a record behind.
    init(client: ASCClient) {
        self.client = client
    }

    /// One language failing does not stop the rest.
    ///
    /// A language added after submission can sit in a different state from the
    /// first one, so App Store Connect can refuse one and accept another. The
    /// alternative, stopping at the first refusal, leaves the listing half
    /// written with nothing saying which half.
    func push(
        _ plan: ChangePlan,
        to listing: RemoteListing,
        localInformation: [String: AppInformation],
        progress: (@Sendable (String) -> Void)? = nil
    ) async -> Result {
        var result = Result()

        for locale in localesInPlan(plan) {
            guard let copy = localInformation[locale] else { continue }
            progress?(locale)

            do {
                let outcome = try await push(copy, locale: locale, to: listing, plan: plan)
                result.refused += outcome.refusals
                // Listed as written only when something actually was.
                if outcome.wroteAnything { result.written.append(locale) }
            } catch {
                result.failed.append(Failure(locale: locale, message: "\(error)"))
            }
        }
        return result
    }

    private func localesInPlan(_ plan: ChangePlan) -> [String] {
        var seen: Set<String> = []
        return plan.textChanges.map(\.locale).filter { seen.insert($0).inserted }
    }

    private func push(
        _ information: AppInformation,
        locale: String,
        to listing: RemoteListing,
        plan: ChangePlan
    ) async throws -> (refusals: [Refusal], wroteAnything: Bool) {
        let changed = Set(plan.textChanges.filter { $0.locale == locale }.map(\.field))
        guard changed.isEmpty == false else { return (refusals: [], wroteAnything: false) }

        var refusals: [Refusal] = []
        var wroteAnything = false

        let appInfoFields = changed.filter(\.isAppInfoField)
        if appInfoFields.isEmpty == false {
            let outcome = try await write(appInfoFields, of: information, locale: locale) {
                try await pushAppInfo(locale: locale, listing: listing, value: $0)
            }
            refusals += outcome.refusals
            wroteAnything = wroteAnything || outcome.wroteAnything
        }

        let versionFields = changed.filter { $0.isAppInfoField == false }
        if versionFields.isEmpty == false {
            let outcome = try await write(versionFields, of: information, locale: locale) {
                try await pushVersion(locale: locale, listing: listing, value: $0)
            }
            refusals += outcome.refusals
            wroteAnything = wroteAnything || outcome.wroteAnything
        }
        return (refusals: refusals, wroteAnything: wroteAnything)
    }

    /// Writes a group of fields, and if App Store Connect refuses one of them
    /// for the state the version is in, writes the rest without it.
    ///
    /// A group goes in one request, so one refused field would otherwise take
    /// the acceptable ones down with it. What's new on a first version does
    /// exactly that, and losing the promotional text alongside it helps nobody.
    private func write(
        _ fields: Set<MetadataField>,
        of information: AppInformation,
        locale: String,
        using send: ((MetadataField) -> String?) async throws -> Void
    ) async throws -> (refusals: [Refusal], wroteAnything: Bool) {
        /// Only fields the plan named are sent. Everything else is left alone
        /// rather than rewritten with the value it already has.
        func values(_ included: Set<MetadataField>) -> (MetadataField) -> String? {
            { included.contains($0) ? information.fields[$0] : nil }
        }

        do {
            try await send(values(fields))
            return (refusals: [], wroteAnything: true)
        } catch {
            let refused = Self.refusedFields(in: error).intersection(fields)
            guard refused.isEmpty == false else { throw error }

            let refusals = refused.sorted { $0.rawValue < $1.rawValue }.map {
                Refusal(locale: locale, field: $0, reason: "\(error)")
            }

            // Every field of this group refused. Nothing to retry, but this is
            // still a named refusal rather than an unexplained failure, and
            // saying which field it was is the whole point of recording it.
            let remaining = fields.subtracting(refused)
            guard remaining.isEmpty == false else {
                return (refusals: refusals, wroteAnything: false)
            }

            try await send(values(remaining))
            return (refusals: refusals, wroteAnything: true)
        }
    }

    private func pushAppInfo(
        locale: String,
        listing: RemoteListing,
        value: (MetadataField) -> String?
    ) async throws {
        guard listing.appInfoID != nil else {
            throw PushError.appInformationNotEditable
        }

        guard let existing = listing.appInfoLocalizations[locale] else {
            throw PushError.noLanguageOnAppStoreConnect(locale: locale)
        }

        _ = try await client.updateAppInfoLocalization(
            id: existing.id,
            name: value(.name),
            subtitle: value(.subtitle),
            privacyPolicyUrl: value(.privacyPolicyUrl)
        )
    }

    private func pushVersion(
        locale: String,
        listing: RemoteListing,
        value: (MetadataField) -> String?
    ) async throws {
        guard let existing = listing.versionLocalizations[locale] else {
            throw PushError.noLanguageOnAppStoreConnect(locale: locale)
        }

        _ = try await client.updateVersionLocalization(
            id: existing.id,
            description: value(.description),
            keywords: value(.keywords),
            whatsNew: value(.whatsNew),
            promotionalText: value(.promotionalText),
            marketingUrl: value(.marketingUrl),
            supportUrl: value(.supportUrl)
        )
    }
}

public enum PushError: Error, CustomLocalizedStringResourceConvertible {
    case appInformationNotEditable

    /// The plan named a language App Store Connect has no page for.
    ///
    /// `Planner` leaves those out, so nothing should reach this. It is here
    /// because the alternative is making the page, and ASCKit never does that.
    case noLanguageOnAppStoreConnect(locale: String)

    case nothingToDo
    case blocked([ChangePlan.Blocked])

    public var localizedStringResource: LocalizedStringResource {
        switch self {
        case let .noLanguageOnAppStoreConnect(locale):
            return LocalizedStringResource("""
            App Store Connect has no \(locale) page, and ASCKit never makes one. \
            Add \(locale) in App Store Connect and read again, or ignore it in this project.
            """, bundle: .here)
        case .appInformationNotEditable:
            return LocalizedStringResource("""
            The name, the subtitle and the privacy policy cannot be changed until a version \
            is in Prepare for Submission.
            """, bundle: .here)
        case .nothingToDo:
            return LocalizedStringResource("Nothing to change.", bundle: .here)
        case let .blocked(blocked):
            let reasons = blocked.map { "  " + String(localized: $0.reason) }.joined(separator: "\n")
            return LocalizedStringResource("This version refuses some of these changes:\n\(reasons)", bundle: .here)
        }
    }
}

extension PushError: CustomStringConvertible {
    public var description: String { String(localized: localizedStringResource) }
}
