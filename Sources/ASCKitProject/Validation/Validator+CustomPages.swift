import ASCKitAPI
import Foundation

public extension Validator {
    /// The files of the custom product pages.
    ///
    /// `keywords` are the keywords each language can use, from the last read.
    /// Without them a keyword is not checked. Whether a page still exists, or
    /// takes changes, is a question for App Store Connect, and the plan
    /// answers it.
    func validate(_ pages: CustomPageContent, keywords: [String: [String]]? = nil) -> [Problem] {
        var problems = validateCustomPageFiles(pages)
        problems += validateCustomPageTexts(pages, keywords: keywords)
        problems += validateCustomPageImages(pages)
        return problems.sortedForDisplay
    }
}

extension Validator {
    private func validateCustomPageFiles(_ pages: CustomPageContent) -> [Problem] {
        var problems: [Problem] = []

        for (url, reason) in pages.unreadable.sorted(by: { $0.key.path < $1.key.path }) {
            let path = Self.customPagePath(of: url) ?? url.lastPathComponent
            problems.append(Problem(
                severity: .error,
                area: .appInformation,
                message: LocalizedStringResource("\(path) does not read: \(reason)", bundle: .here),
                fix: LocalizedStringResource("Nothing in it is pushed until it reads.", bundle: .here),
                path: path,
                kind: .customPageFileUnreadable
            ))
        }

        for (page, settings) in pages.settings.sorted(by: { $0.key < $1.key }) {
            guard let link = settings.deepLink?.trimmingCharacters(in: .whitespacesAndNewlines),
                  link.isEmpty == false
            else { continue }
            if URL(string: link)?.scheme?.isEmpty != false {
                let path = "\(CustomPageFolders.folderName)/\(page)/\(CustomPageFolders.settingsFileName)"
                problems.append(Problem(
                    severity: .error,
                    area: .appInformation,
                    message: LocalizedStringResource("The deep link of \(page) is not an address.", bundle: .here),
                    fix: LocalizedStringResource(
                        "Use a universal link or a link with your app's own scheme, such as myapp://moon.",
                        bundle: .here
                    ),
                    path: path,
                    kind: .customPageDeepLinkNotValid
                ))
            }
        }
        return problems
    }

    private func validateCustomPageTexts(
        _ pages: CustomPageContent,
        keywords: [String: [String]]?
    ) -> [Problem] {
        var problems: [Problem] = []

        for (page, texts) in pages.texts.sorted(by: { $0.key < $1.key }) {
            for (locale, text) in texts.sorted(by: { $0.key < $1.key }) {
                let path = "\(CustomPageFolders.folderName)/\(page)/\(CustomPageFolders.textFolderName)/\(locale).json"

                // The same limits as the promotional text of a version.
                if let promotionalText = text.promotionalText {
                    var copy = AppInformation(locale: locale)
                    copy.fields[.promotionalText] = promotionalText
                    problems += validateFields(copy, locale: locale, path: path)
                }

                guard let known = keywords?[locale].map(Set.init) else { continue }
                for keyword in text.keywords ?? [] where known.contains(keyword) == false {
                    problems.append(Problem(
                        severity: .warning,
                        area: .appInformation,
                        message: LocalizedStringResource(
                            "\(page) links the keyword \(keyword), which the version on sale does not have.",
                            bundle: .here
                        ),
                        fix: LocalizedStringResource("""
                        A page can use only the keywords of the version on sale. \
                        Take it off, or wait until a version with it is on sale.
                        """, bundle: .here),
                        locale: locale,
                        path: path,
                        kind: .customPageKeywordNotKnown
                    ))
                }
            }
        }
        return problems
    }

    /// The same checks as the images of a test: what App Store Connect
    /// refuses, and nothing about whether the page exists.
    private func validateCustomPageImages(_ pages: CustomPageContent) -> [Problem] {
        var problems = validateScreenshotSets(pages.screenshots.map { $0.key.placed($0.value) })
        problems += validatePreviewSets(pages.previews.map { $0.key.placed($0.value) })

        for page in pages.creative.keys.sorted() {
            problems += validateCreativeFolder(
                pages.creative[page] ?? CreativeFolder(),
                root: "\(CustomPageFolders.folderName)/\(page)/\(CreativeFolder.folderName)"
            )
        }
        return problems
    }

    /// The path of a file below the pages folder, as a problem names it.
    private static func customPagePath(of url: URL) -> String? {
        let parts = url.standardizedFileURL.pathComponents
        guard let index = parts.lastIndex(of: CustomPageFolders.folderName) else { return nil }
        return parts[index...].joined(separator: "/")
    }
}
