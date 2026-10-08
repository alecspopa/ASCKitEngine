import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// One sentence about a failure, meant for a person rather than for a log.
public enum ErrorMessage {
    /// Every error this app throws writes its own sentence, so it is asked for
    /// one. An error from Foundation keeps its sentence in
    /// `localizedDescription`. Printing such an error gives the whole `NSError`
    /// dump instead, with codes, URLs and session task names in it, which is
    /// what a person should never see.
    public static func text(for error: any Error) -> String {
        switch error {
        case is CancellationError:
            String(localized: stopped)
        case let error as URLError:
            String(localized: network(error))
        case let error as CocoaError:
            error.localizedDescription
        case let error as any CustomStringConvertible:
            error.description
        default:
            error.localizedDescription
        }
    }

    static var stopped: LocalizedStringResource {
        LocalizedStringResource("The request stopped before it finished. Try again.", bundle: .here)
    }

    /// A length of time in words, rounded the way a person says it.
    ///
    /// One sentence per unit, so the catalog can hold the plural rule for each
    /// one. English wants two forms and other languages want more.
    public static func spellOut(_ duration: Duration) -> String {
        let seconds = Int(duration.components.seconds)
        if seconds < 1 { return String(localized: "a moment", bundle: .module) }
        if seconds < 90 { return String(localized: "\(seconds) seconds", bundle: .module) }

        let minutes = Int((Double(seconds) / 60).rounded())
        if minutes < 90 { return String(localized: "\(minutes) minutes", bundle: .module) }

        let hours = Int((Double(minutes) / 60).rounded())
        return String(localized: "\(hours) hours", bundle: .module)
    }

    /// URLSession says what went wrong in a number, so this says it in words.
    static func network(_ error: URLError) -> LocalizedStringResource {
        switch error.code {
        case .cancelled:
            stopped
        case .notConnectedToInternet:
            LocalizedStringResource("No internet connection, so ASCKit cannot reach App Store Connect.", bundle: .here)
        case .timedOut:
            LocalizedStringResource("App Store Connect took too long to answer. Try again.", bundle: .here)
        case .networkConnectionLost, .cannotConnectToHost, .cannotFindHost, .dnsLookupFailed:
            LocalizedStringResource("The connection to App Store Connect dropped. Try again.", bundle: .here)
        case .secureConnectionFailed, .serverCertificateUntrusted:
            LocalizedStringResource("The secure connection to App Store Connect failed.", bundle: .here)
        default:
            LocalizedStringResource("ASCKit cannot reach App Store Connect. \(error.localizedDescription)", bundle: .here)
        }
    }
}

public extension Error {
    /// True when this app stopped its own work, rather than something going
    /// wrong.
    ///
    /// A window that closes cancels the read it started, and a task group
    /// cancels the children of a child that threw. URLSession reports a
    /// cancelled request as `URLError.cancelled`, which reads like a failure
    /// and is not one. Both shapes mean the same thing here.
    var isCancellation: Bool {
        if self is CancellationError { return true }
        if let error = self as? URLError, error.code == .cancelled { return true }
        return false
    }
}

public extension Collection<any Error> {
    /// The one worth showing when several requests failed together.
    ///
    /// A cancellation is usually caused by another error in the same group, so
    /// reporting it names the effect and hides the reason.
    var mostTelling: (any Error)? {
        first { $0.isCancellation == false } ?? first
    }
}
