import Foundation

/// Saying that a language shows the source language's header and search
/// results art.
///
/// The answer lives in `asckit.json`, as `usesSourceScreenshots` does, because
/// it holds for every version.
public enum SourceCreative {
    /// Turns the decision on or off for one language.
    @discardableResult
    public static func set(_ showsSource: Bool, locale: String, in project: Project) throws -> ProjectConfig {
        guard locale != project.config.sourceLocale else {
            throw SourceScreenshotError.sourceLanguage(locale)
        }

        var config = project.config
        var listed = config.usesSourceCreative.filter { $0 != locale }
        if showsSource { listed.append(locale) }
        config.usesSourceCreative = listed.sorted()

        if config != project.config { try project.write(config) }
        return config
    }
}
