import Foundation

/// The locale codes App Store Connect accepts for metadata.
///
/// The scheme is not consistent: Italian is `it` and Japanese is `ja` with no
/// region, while Dutch is `nl-NL` and German is `de-DE` with one. App Store
/// Connect skips an unknown code silently instead of rejecting it, so a run
/// looks successful and uploads nothing. That is why this table is written out
/// rather than derived from `Locale`.
///
/// Taken from Apple's "Managing metadata in your app by using locale
/// shortcodes". `asckit pull` reports what the API returns for a given app, so
/// a code missing here can be checked against the real thing.
public enum StoreLocale {
    public struct Entry: Sendable, Hashable, Identifiable {
        public let code: String
        public let englishName: String

        public var id: String { code }
    }

    public static let all: [Entry] = [
        Entry(code: "ar-SA", englishName: "Arabic"),
        Entry(code: "bn-BD", englishName: "Bengali"),
        Entry(code: "ca", englishName: "Catalan"),
        Entry(code: "cs", englishName: "Czech"),
        Entry(code: "da", englishName: "Danish"),
        Entry(code: "de-DE", englishName: "German"),
        Entry(code: "el", englishName: "Greek"),
        Entry(code: "en-AU", englishName: "English (Australia)"),
        Entry(code: "en-CA", englishName: "English (Canada)"),
        Entry(code: "en-GB", englishName: "English (U.K.)"),
        Entry(code: "en-US", englishName: "English (U.S.)"),
        Entry(code: "es-ES", englishName: "Spanish (Spain)"),
        Entry(code: "es-MX", englishName: "Spanish (Mexico)"),
        Entry(code: "fi", englishName: "Finnish"),
        Entry(code: "fr-CA", englishName: "French (Canada)"),
        Entry(code: "fr-FR", englishName: "French"),
        Entry(code: "gu-IN", englishName: "Gujarati"),
        Entry(code: "he", englishName: "Hebrew"),
        Entry(code: "hi", englishName: "Hindi"),
        Entry(code: "hr", englishName: "Croatian"),
        Entry(code: "hu", englishName: "Hungarian"),
        Entry(code: "id", englishName: "Indonesian"),
        Entry(code: "it", englishName: "Italian"),
        Entry(code: "ja", englishName: "Japanese"),
        Entry(code: "kn-IN", englishName: "Kannada"),
        Entry(code: "ko", englishName: "Korean"),
        Entry(code: "ml-IN", englishName: "Malayalam"),
        Entry(code: "mr-IN", englishName: "Marathi"),
        Entry(code: "ms", englishName: "Malay"),
        Entry(code: "nl-NL", englishName: "Dutch"),
        Entry(code: "no", englishName: "Norwegian"),
        Entry(code: "or-IN", englishName: "Odia"),
        Entry(code: "pa-IN", englishName: "Punjabi"),
        Entry(code: "pl", englishName: "Polish"),
        Entry(code: "pt-BR", englishName: "Portuguese (Brazil)"),
        Entry(code: "pt-PT", englishName: "Portuguese (Portugal)"),
        Entry(code: "ro", englishName: "Romanian"),
        Entry(code: "ru", englishName: "Russian"),
        Entry(code: "sk", englishName: "Slovak"),
        Entry(code: "sl-SI", englishName: "Slovenian"),
        Entry(code: "sv", englishName: "Swedish"),
        Entry(code: "ta-IN", englishName: "Tamil"),
        Entry(code: "te-IN", englishName: "Telugu"),
        Entry(code: "th", englishName: "Thai"),
        Entry(code: "tr", englishName: "Turkish"),
        Entry(code: "uk", englishName: "Ukrainian"),
        Entry(code: "ur-PK", englishName: "Urdu"),
        Entry(code: "vi", englishName: "Vietnamese"),
        Entry(code: "zh-Hans", englishName: "Chinese (Simplified)"),
        Entry(code: "zh-Hant", englishName: "Chinese (Traditional)")
    ]

    private static let byCode: [String: Entry] = Dictionary(
        uniqueKeysWithValues: all.map { ($0.code, $0) }
    )

    public static func isKnown(_ code: String) -> Bool {
        byCode[code] != nil
    }

    /// The language a code is written in, keeping a script such as `Hans`.
    ///
    /// `en-US` and `en-GB` both answer `en`, because they are one language and
    /// one can show the other's screenshots. `zh-Hans` and `zh-Hant` answer
    /// themselves, because a different script is a different picture.
    public static func baseLanguage(of code: String) -> String {
        let parts = code.split(separator: "-").map(String.init)
        guard let language = parts.first else { return code }
        guard parts.count > 1, parts[1].count == 4, parts[1].allSatisfy(\.isLetter) else {
            return language
        }
        return "\(language)-\(parts[1])"
    }

    public static func englishName(for code: String) -> String? {
        byCode[code]?.englishName
    }

    /// The code someone probably meant, for a message that helps rather than
    /// just refusing. `ja-JP` should suggest `ja`, `nl` should suggest `nl-NL`.
    public static func suggestion(for code: String) -> String? {
        if isKnown(code) { return nil }
        let language = code.split(separator: "-").first.map(String.init) ?? code
        let matches = all.filter { entry in
            entry.code == language || entry.code.hasPrefix("\(language)-")
        }
        return matches.count == 1 ? matches[0].code : nil
    }
}
