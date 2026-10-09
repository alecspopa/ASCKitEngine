import Foundation

/// Saying that a language shows the source language's screenshots.
///
/// App Store Connect shows the primary language's screenshots to anybody whose
/// language has none of its own, one display type at a time. So an empty folder
/// is either a gap or a decision, and only somebody who knows the app can say
/// which. This is where they say it.
///
/// The answer lives in `asckit.json` rather than in a version folder, because
/// it is about how the app is translated rather than about one release. It
/// holds for every version, including the ones not made yet.
public enum SourceScreenshots {
    /// Turns the decision on or off for one language and one device class.
    ///
    /// Writes the configuration file and returns what it wrote, so a caller can
    /// carry on without reading the folder again.
    @discardableResult
    public static func set(
        _ showsSource: Bool,
        locale: String,
        deviceClassID: String,
        in project: Project
    ) throws -> ProjectConfig {
        guard locale != project.config.sourceLocale else {
            throw SourceScreenshotError.sourceLanguage(locale)
        }

        var config = project.config
        var listed = config.usesSourceScreenshots[locale] ?? []

        if showsSource {
            guard listed.contains(deviceClassID) == false else { return config }
            listed.append(deviceClassID)
            config.usesSourceScreenshots[locale] = listed.sorted()
        } else {
            listed.removeAll { $0 == deviceClassID }
            // The key goes when the last device class does, so a language that
            // shows nothing of the source's leaves nothing behind in the file.
            config.usesSourceScreenshots[locale] = listed.isEmpty ? nil : listed
        }

        try project.write(config)
        return config
    }
}

public enum SourceScreenshotError: Error, CustomLocalizedStringResourceConvertible {
    case sourceLanguage(String)

    public var localizedStringResource: LocalizedStringResource {
        switch self {
        case let .sourceLanguage(locale):
            LocalizedStringResource("""
            \(locale) is the source language. Every other language falls back to it, \
            and it has nothing to fall back to.
            """, bundle: .here)
        }
    }
}

extension SourceScreenshotError: CustomStringConvertible {
    public var description: String { String(localized: localizedStringResource) }
}
