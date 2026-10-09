import Foundation

/// What Apple reports in the `X-Rate-Limit` header on every response.
///
/// The format is key-value pairs joined by semicolons, for example
/// `user-hour-lim:3500;user-hour-rem:500;`. Apple documents 3500 but adds that
/// actual limits vary, so read the header rather than assuming the number.
public struct RateLimit: Sendable, Hashable {
    public let limitPerHour: Int?
    public let remainingThisHour: Int?

    /// How long App Store Connect said to wait, out of the `Retry-After`
    /// header. Nil when it named no wait, which is most of the time.
    public let retryAfter: Duration?

    public init(limitPerHour: Int?, remainingThisHour: Int?, retryAfter: Duration? = nil) {
        self.limitPerHour = limitPerHour
        self.remainingThisHour = remainingThisHour
        self.retryAfter = retryAfter
    }

    /// Returns nil when the header is missing or carries nothing we recognise.
    public init?(headerValue: String, retryAfter: Duration? = nil) {
        var values: [String: Int] = [:]
        for pair in headerValue.split(separator: ";") {
            let parts = pair.split(separator: ":", maxSplits: 1)
            guard parts.count == 2, let number = Int(parts[1].trimmingCharacters(in: .whitespaces)) else {
                continue
            }
            values[parts[0].trimmingCharacters(in: .whitespaces)] = number
        }
        guard values.isEmpty == false else { return nil }
        self.init(
            limitPerHour: values["user-hour-lim"],
            remainingThisHour: values["user-hour-rem"],
            retryAfter: retryAfter
        )
    }

    public init?(response: HTTPURLResponse) {
        let wait = Self.retryAfter(in: response)
        let counts = response.value(forHTTPHeaderField: "X-Rate-Limit").flatMap {
            RateLimit(headerValue: $0)
        }
        guard counts != nil || wait != nil else { return nil }

        self.init(
            limitPerHour: counts?.limitPerHour,
            remainingThisHour: counts?.remainingThisHour,
            retryAfter: wait
        )
    }

    /// A run across every language and device class is request-heavy, so the
    /// caller may want to slow down before Apple starts refusing.
    public var isRunningLow: Bool {
        guard let remainingThisHour, let limitPerHour, limitPerHour > 0 else { return false }
        return Double(remainingThisHour) / Double(limitPerHour) < 0.1
    }

    /// `Retry-After` carries either a number of seconds or a date to wait for.
    ///
    /// A date already gone by means wait no longer, so both shapes end up as a
    /// length of time that is never negative.
    private static func retryAfter(in response: HTTPURLResponse) -> Duration? {
        let header = response.value(forHTTPHeaderField: "Retry-After")?
            .trimmingCharacters(in: .whitespaces)
        guard let header, header.isEmpty == false else { return nil }

        if let seconds = Double(header) {
            return .seconds(max(0, seconds))
        }

        // Built here rather than kept around, because a date is the rarer of
        // the two shapes and a DateFormatter cannot be shared across tasks.
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"

        guard let date = formatter.date(from: header) else { return nil }
        return .seconds(max(0, date.timeIntervalSinceNow))
    }
}
