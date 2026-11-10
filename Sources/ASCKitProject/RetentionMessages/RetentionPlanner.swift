import ASCKitAPI
import Foundation

/// Works out what a push would do to the words of the retention messages.
///
/// ASCKit writes only a message that is not yet published. It never makes a
/// message, a version or a draft.
enum RetentionPlanner {
    struct Outcome {
        let changes: [ChangePlan.RetentionTextChange]
        let blocked: [ChangePlan.Blocked]
        let skipped: [ChangePlan.Skipped]
    }

    static func plan(local: ProductCatalog, config: ProjectConfig, remote: RemoteProducts) -> Outcome {
        var changes: [ChangePlan.RetentionTextChange] = []
        var blocked: [ChangePlan.Blocked] = []
        var skipped: [ChangePlan.Skipped] = []
        let onStore = remote.retentionMessagesByName

        for message in local.sortedRetentionMessages {
            let name = message.referenceName
            guard let match = onStore[name] else {
                blocked.append(ChangePlan.Blocked(
                    reason: LocalizedStringResource("""
                    App Store Connect has no retention message called \(name), and \
                    ASCKit never makes one.
                    """, bundle: .here),
                    affects: LocalizedStringResource("\(name)", bundle: .here),
                    cause: .product,
                    parts: [.purchases]
                ))
                continue
            }

            guard message.status.canPublish else {
                skipped.append(ChangePlan.Skipped(
                    locale: name,
                    reason: LocalizedStringResource("marked \(message.status.rawValue)", bundle: .here)
                ))
                continue
            }

            let wordChanges = words(of: message, against: match.version, config: config)
            guard wordChanges.isEmpty == false else { continue }

            guard let version = match.version, version.acceptsChanges else {
                let state = StateWords.readable(match.version?.state?.rawValue ?? "")
                blocked.append(ChangePlan.Blocked(
                    reason: LocalizedStringResource("""
                    The retention message \(name) is \(state). ASCKit changes only a \
                    message that is not yet published. Make a new version in App Store \
                    Connect to change it.
                    """, bundle: .here),
                    affects: LocalizedStringResource("\(name)", bundle: .here),
                    cause: .product,
                    parts: [.purchases]
                ))
                continue
            }
            changes += wordChanges
        }
        return Outcome(changes: changes, blocked: blocked, skipped: skipped)
    }

    private static func words(
        of message: RetentionMessage,
        against version: RemoteRetentionVersion?,
        config: ProjectConfig
    ) -> [ChangePlan.RetentionTextChange] {
        var changes: [ChangePlan.RetentionTextChange] = []

        for locale in config.writtenLocales.sorted() {
            guard let written = message.localizations[locale] else { continue }
            let remote = version?.words[locale]

            for field in RetentionField.allCases {
                guard let newValue = written[field] else { continue }
                let oldValue = field == .header ? remote?.header : remote?.body

                if let oldValue, oldValue.isEmpty == false {
                    guard oldValue != newValue else { continue }
                    changes.append(.init(
                        message: message.referenceName, locale: locale, field: field,
                        action: .change, oldValue: oldValue, newValue: newValue
                    ))
                } else {
                    guard newValue.isEmpty == false else { continue }
                    changes.append(.init(
                        message: message.referenceName, locale: locale, field: field,
                        action: .add, oldValue: nil, newValue: newValue
                    ))
                }
            }
        }
        return changes
    }
}
