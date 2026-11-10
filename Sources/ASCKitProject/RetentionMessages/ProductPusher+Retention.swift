import ASCKitAPI
import Foundation

/// Writing the header and body of the retention messages.
extension ProductPusher {
    /// One language failing does not stop the rest. A message that is no longer
    /// open for changes is refused whole.
    func pushRetentionWords(
        _ plan: ChangePlan,
        to remote: RemoteProducts,
        dryRun: Bool,
        progress: (@Sendable (String) -> Void)?,
        into result: inout TextResult
    ) async {
        let byName = remote.retentionMessagesByName
        var grouped: [String: [String: [RetentionField: String]]] = [:]
        for change in plan.retentionTextChanges {
            grouped[change.message, default: [:]][change.locale, default: [:]][change.field] = change.newValue
        }

        for (name, changes) in grouped.sorted(by: { $0.key < $1.key }) {
            guard let version = byName[name]?.version, version.acceptsChanges else {
                result.failed.append(Failure(
                    productID: name,
                    what: "",
                    reason: String(localized: "App Store Connect no longer takes changes to this retention message.",
                                   bundle: .module)
                ))
                continue
            }
            result.drafts.append(Draft(productID: name, versionID: version.id, number: nil))

            for (locale, fields) in changes.sorted(by: { $0.key < $1.key }) {
                progress?("\(name), \(locale)")
                let words = RetentionWordsWrite(header: fields[.header], body: fields[.body])
                let existing = version.words[locale]

                if dryRun {
                    result.wouldSend.append(existing.map { RetentionWritePreview.wordsChange(id: $0.id, words) }
                        ?? RetentionWritePreview.words(versionID: version.id, Self.newRow(words, locale: locale)))
                    continue
                }
                do {
                    if let existing {
                        try await client.updateRetentionWords(id: existing.id, words)
                    } else {
                        try await client.createRetentionWords(versionID: version.id, Self.newRow(words, locale: locale))
                    }
                    result.written.append("\(name) \(locale)")
                } catch {
                    result.failed.append(Failure(productID: name, what: locale, reason: ErrorMessage.text(for: error)))
                }
            }
        }
    }

    private static func newRow(_ words: RetentionWordsWrite, locale: String) -> RetentionWordsWrite {
        RetentionWordsWrite(locale: locale, header: words.header, body: words.body)
    }
}
