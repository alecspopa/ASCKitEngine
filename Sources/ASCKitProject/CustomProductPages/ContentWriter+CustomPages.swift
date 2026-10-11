import Foundation

// MARK: - Writing the text

public extension ContentWriter {
    /// Writes the words of one language of a page. A field that is nil is
    /// left out of the file, and so left alone on App Store Connect.
    static func writeCustomPageText(_ text: CustomPageText, page: String, in project: Project) throws {
        try ProjectJSON.write(text, to: project.customPageTextURL(page: page, locale: text.locale), atomic: true)
    }

    static func writeCustomPageSettings(_ settings: CustomPageSettings, page: String, in project: Project) throws {
        try ProjectJSON.write(settings, to: project.customPageSettingsURL(page: page), atomic: true)
    }
}
