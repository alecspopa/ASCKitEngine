import Foundation

/// Whether one part of a push can go, and what to say beside it.
public enum PublishAvailability: Sendable, Equatable {
    /// Something to write, with what, at a glance.
    case ready(String)

    /// Nothing to write. The files here already match App Store Connect, which
    /// is not a refusal.
    case nothingToDo

    /// Cannot go, and why, in a sentence a person can act on.
    case blocked(String)

    public var canGo: Bool {
        if case .ready = self { return true }
        return false
    }

    /// The line under the name of the part.
    ///
    /// A `String` rather than a `LocalizedStringResource`, because the two
    /// cases that carry one hold a sentence `PublishReadiness` has already
    /// resolved.
    public var detail: String {
        switch self {
        case let .ready(count): count
        case .nothingToDo: String(localized: "No change.", bundle: .module)
        case let .blocked(reason): reason
        }
    }
}
