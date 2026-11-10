import ASCKitAPI
import Foundation

/// Turns the retention messages App Store Connect holds into message files.
///
/// Writes over nothing unless told to, like `ProductSnapshot`. A message with
/// no words still gets a file, because the file is where a person writes them.
/// The image stays on App Store Connect: a pull writes words only.
public enum RetentionSnapshot {
    public struct Outcome: Sendable {
        public let written: [String]
        /// Already on disk, so left exactly as it was.
        public let left: [String]
        /// Names that cannot be a file name, with the reason.
        public let refused: [(name: String, reason: String)]

        public var isEmpty: Bool { written.isEmpty && left.isEmpty && refused.isEmpty }
    }

    public static func write(
        _ remote: [RemoteRetentionMessage],
        to project: Project,
        overwrite: Bool = false
    ) throws -> Outcome {
        let existing = ProductStore.load(in: project)
        var written: [String] = []
        var left: [String] = []
        var refused: [(name: String, reason: String)] = []

        for message in remote.sorted(by: { $0.referenceName < $1.referenceName }) {
            let name = message.referenceName
            if let reason = ProductStore.reasonToRefuse(retentionName: name) {
                refused.append((name, reason))
                continue
            }
            guard overwrite || existing.retentionMessages[name] == nil else {
                left.append(name)
                continue
            }
            try ContentWriter.writeRetentionMessage(make(message, config: project.config), in: project)
            written.append(name)
        }
        return Outcome(written: written, left: left, refused: refused)
    }

    /// `needs_human` for the reason `ProductSnapshot.make` gives.
    public static func make(_ remote: RemoteRetentionMessage, config: ProjectConfig) -> RetentionMessage {
        var words: [String: RetentionMessage.Localization] = [:]
        for (locale, written) in remote.version?.words ?? [:] where config.writtenLocales.contains(locale) {
            words[locale] = RetentionMessage.Localization(header: written.header, body: written.body)
        }
        return RetentionMessage(referenceName: remote.referenceName, status: .needsHuman, localizations: words)
    }
}
