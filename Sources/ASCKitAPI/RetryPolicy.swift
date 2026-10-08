import Foundation

/// How hard to try again after a rate limit or a server error.
///
/// Apple returns 500 in places where a 4xx belongs, so a retry is often the
/// right first move. A 403 is never worth retrying, which `ASCError` decides.
public struct RetryPolicy: Sendable, Hashable {
    public var maximumAttempts: Int
    public var initialDelay: Duration
    public var multiplier: Double

    /// The longest wait this sits through when App Store Connect names one in
    /// a `Retry-After` header. A longer wait is reported instead, because a
    /// window that does nothing for ten minutes reads as a broken one.
    public var maximumWait: Duration

    public init(
        maximumAttempts: Int = 4,
        initialDelay: Duration = .seconds(1),
        multiplier: Double = 2,
        maximumWait: Duration = .seconds(60)
    ) {
        self.maximumAttempts = maximumAttempts
        self.initialDelay = initialDelay
        self.multiplier = multiplier
        self.maximumWait = maximumWait
    }

    /// One attempt, no waiting. What tests use.
    public static let none = RetryPolicy(maximumAttempts: 1, initialDelay: .zero, multiplier: 1)

    /// Every attempt, no waiting. What a test of the retrying itself uses, so
    /// that it finishes in the time one request takes.
    public static let immediate = RetryPolicy(maximumAttempts: 4, initialDelay: .zero, multiplier: 1)

    func delay(beforeAttempt attempt: Int) -> Duration {
        guard attempt > 1 else { return .zero }
        let factor = pow(multiplier, Double(attempt - 2))
        return initialDelay * factor
    }
}
