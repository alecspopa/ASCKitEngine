import Foundation

/// A plain day written as `2026-08-30`. Always read and counted in UTC, so the
/// answer does not change with the time zone of the machine.
enum CalendarDay {
    /// POSIX so a person whose calendar is not Gregorian still gets 2026-08-30.
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }()

    /// Midnight UTC of the day, or nil when the text is not a day.
    static func date(from text: String) -> Date? {
        formatter.date(from: text)
    }

    static func string(from date: Date) -> String {
        formatter.string(from: date)
    }

    /// Whole days from one date to the other.
    static func daysBetween(_ start: Date, _ end: Date) -> Int {
        calendar.dateComponents([.day], from: start, to: end).day ?? 0
    }
}
