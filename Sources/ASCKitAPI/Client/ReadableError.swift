import Foundation

/// An error that a person reads. Its description is its localized sentence,
/// so a log line and the app say the same thing.
public protocol ReadableError: Error, CustomLocalizedStringResourceConvertible, CustomStringConvertible {}

public extension ReadableError {
    var description: String { String(localized: localizedStringResource) }
}
