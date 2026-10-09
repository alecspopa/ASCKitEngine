import ASCKitAPI
import Foundation

/// Writes the deep links, the promotional text and the keyword links of the
/// custom product pages.
///
/// Works from a plan rather than from the files, so what is written is exactly
/// what was shown before anyone agreed to it.
public struct CustomPageTextPusher: Sendable {
    public struct Result: Sendable {
        /// One line for each page or language written, such as
        /// `Night sky / en-US`.
        public var written: [String] = []
        public var failed: [Failure] = []

        public var isCompleteSuccess: Bool { failed.isEmpty }
    }

    public struct Failure: Sendable {
        public let label: String
        public let message: String
    }

    private let client: ASCClient

    /// Reachable only from inside the package, so every push goes through
    /// `PushSession` and leaves a record behind.
    init(client: ASCClient) {
        self.client = client
    }

    /// One page or language failing does not stop the rest.
    func push(_ plan: CustomPagePlan, progress: (@Sendable (String) -> Void)? = nil) async -> Result {
        var result = Result()

        for change in plan.deepLinkChanges {
            progress?(change.pageName)
            do {
                try await client.updateCustomPageVersion(id: change.versionID, deepLink: change.deepLink)
                result.written.append(change.pageName)
            } catch {
                result.failed.append(Failure(label: change.pageName, message: "\(error)"))
            }
        }

        for change in plan.changingTexts {
            progress?(change.label)
            do {
                try await push(change)
                result.written.append(change.label)
            } catch {
                result.failed.append(Failure(label: change.label, message: "\(error)"))
            }
        }
        return result
    }

    /// Unlinks before it links. A page that holds as many keywords as App
    /// Store Connect allows has room for a new one only after an old one goes.
    private func push(_ change: CustomPagePlan.TextChange) async throws {
        if let text = change.promotionalText {
            try await client.updateCustomPageLocalization(id: change.localizationID, promotionalText: text)
        }
        if change.keywordsToUnlink.isEmpty == false {
            try await client.unlinkKeywords(change.keywordsToUnlink, localizationID: change.localizationID)
        }
        if change.keywordsToLink.isEmpty == false {
            try await client.linkKeywords(change.keywordsToLink, localizationID: change.localizationID)
        }
    }
}
