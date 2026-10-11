import Foundation

public extension ASCClient {
    /// What App Store Connect says about the pages, with the ids, as lines for
    /// a terminal. English, because a terminal reads it.
    ///
    /// A person reads this to see what a keyword id looks like and which
    /// placements a page takes. It reads every version of every page, not only
    /// the one that shows.
    func customPageProbe(bundleID: String) async throws -> [String] {
        let unknownState = "state unknown"
        let remote = try await customPages(bundleID: bundleID)
        var lines = ["app \(remote.appID)"]

        for page in try await customPages(appID: remote.appID) {
            let attributes = page.attributes
            lines.append("")
            lines.append("page \(page.id) \"\(attributes?.name ?? "")\" visible=\(attributes?.visible.map(String.init) ?? "nil")")
            lines.append("  url \(attributes?.url ?? "nil")")
            for version in try await customPageVersions(pageID: page.id) {
                let state = version.attributes?.state?.rawValue ?? unknownState
                lines.append("  version \(version.id) \(version.attributes?.version ?? "nil") \(state)"
                    + " deepLink=\(version.attributes?.deepLink ?? "nil")")
            }
            guard let shown = remote.page(id: page.id)?.version else { continue }
            lines.append("  shown version \(shown.id)")
            for localization in shown.localizations {
                lines.append("    \(localization.locale) \(localization.id)")
                lines.append("      promotionalText: \(localization.promotionalText ?? "nil")")
                lines.append("      keywords: \(localization.keywordIDs)")
                for placement in localization.placements {
                    lines.append("      placement \(placement.type?.rawValue ?? "nil") \(placement.group ?? "nil")")
                }
            }
        }

        lines.append("")
        for (locale, keywords) in remote.keywords.sorted(by: { $0.key < $1.key }) {
            lines.append("app keywords \(locale): \(keywords)")
        }

        for version in try await appStoreVersions(appID: remote.appID, platform: .ios) {
            let string = version.attributes?.versionString ?? "nil"
            let state = version.attributes?.appVersionState?.rawValue ?? unknownState
            lines.append("")
            lines.append("version \(string) \(state)")
            for localization in try await versionLocalizations(versionID: version.id) {
                let locale = localization.attributes?.locale ?? "nil"
                let keywords = try await versionKeywordIDs(localizationID: localization.id)
                lines.append("  \(locale) text: \(localization.attributes?.keywords ?? "nil")")
                lines.append("  \(locale) ids: \(keywords)")
            }
        }
        return lines
    }
}
