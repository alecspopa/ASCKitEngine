import Foundation

/// "1 file" or "3 files". Foundation agrees the noun with the count, so no
/// caller makes a plural by hand. The locale is English because the command line
/// has no translations.
public func countedNoun(_ count: Int, _ noun: String) -> String {
    String(AttributedString(localized: "^[\(count) \(noun)](inflect: true)", locale: Locale(identifier: "en")).characters)
}
