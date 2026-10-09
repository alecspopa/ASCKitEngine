import Foundation

/// Saying that a language is the app's and not the store's.
///
/// An app is often built in more languages than its store page is written in.
/// The Xcode project ships Romanian, and nobody is going to write a Romanian
/// store page. Left alone, that language is a warning on every run: the checker
/// sees the app built in it and asks for a listing to match.
///
/// Ignoring it is the answer. The name stays in `locales`, so the checker still
/// knows the app is built in it and stops asking. Nothing is written for it,
/// nothing is checked about it, and App Store Connect never hears about it.
/// The files it already had move to the Trash, because a folder holding words
/// nothing reads is a folder somebody will edit by mistake.
///
/// The decision lives in `asckit.json`, beside the language list it is about,
/// because it is about how the app is translated rather than about one release.
/// The app and the `asckit ignore` command both write through here, so a
/// language ignored in the terminal is ignored in the window.
public enum IgnoredLocales {
    /// Ignores this language, or takes the ignore back.
    ///
    /// Writes the configuration file and answers with what it wrote, so a
    /// caller can carry on without reading the folder again. Asking for what is
    /// already true writes nothing.
    ///
    /// Ignoring also moves this language's files to the Trash. Taking the
    /// ignore back writes no file here. The caller reads App Store Connect
    /// again, which is the only place the words still are.
    @discardableResult
    public static func set(
        _ ignored: Bool,
        locale: String,
        in project: Project
    ) throws -> ProjectConfig {
        var config = project.config

        if ignored {
            guard locale != config.sourceLocale else {
                throw IgnoredLocaleError.sourceLanguage(locale)
            }
            guard config.locales.contains(locale) else {
                throw IgnoredLocaleError.notListed(locale, listed: config.locales)
            }
            guard config.isIgnored(locale) == false else { return config }
            config.ignoredLocales.append(locale)
            // Sorted, unlike `locales`. The order of the language list is the
            // order the sidebar shows and the order a push writes in. This list
            // is read as a set and shows nowhere, so a stable order is worth
            // more than the order somebody typed the names in.
            config.ignoredLocales.sort()
        } else {
            guard config.isIgnored(locale) else { return config }
            config.ignoredLocales.removeAll { $0 == locale }
        }

        try project.write(config)
        if ignored { try trashFiles(locale: locale, in: project) }
        return config
    }

    /// Moves one language's text and screenshots to the Trash, in every version
    /// folder the project has.
    ///
    /// The Trash rather than a delete, so a language ignored by mistake is one
    /// drag away from coming back. A file that is not there is not an error.
    @discardableResult
    public static func trashFiles(locale: String, in project: Project) throws -> [URL] {
        var trashed: [URL] = []

        for version in try project.versionNames() {
            let candidates = [
                project.informationURL(version: version, locale: locale),
                project.screenshotsURL(version: version).appending(path: locale)
            ]

            for url in candidates where FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                trashed.append(url)
            }
        }
        return trashed
    }
}

public enum IgnoredLocaleError: Error, Equatable, CustomLocalizedStringResourceConvertible {
    case sourceLanguage(String)
    case notListed(String, listed: [String])

    public var localizedStringResource: LocalizedStringResource {
        switch self {
        case let .sourceLanguage(locale):
            LocalizedStringResource("""
            \(locale) is the source language. Every other language is translated from it, \
            and a listing with no source language has nothing to say.
            """, bundle: .here)
        case let .notListed(locale, listed):
            LocalizedStringResource("""
            This project has no \(locale). It lists \(listed.formatted(.list(type: .and))).
            """, bundle: .here)
        }
    }
}

extension IgnoredLocaleError: CustomStringConvertible {
    public var description: String { String(localized: localizedStringResource) }
}
