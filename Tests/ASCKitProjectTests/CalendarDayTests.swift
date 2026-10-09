import Foundation
import Testing
@testable import ASCKitProject

struct CalendarDayTests {
    private static let curve = PriceCurve(
        id: "test",
        displayName: "Test",
        summary: "A curve for a test.",
        bands: [],
        provenance: .init(source: "A test.", takenOn: "2025-01-01")
    )

    private func provenanceProblems(daysOld: Int) throws -> [Problem] {
        let taken = try #require(CalendarDay.date(from: "2025-01-01"))
        let now = try #require(Calendar(identifier: .gregorian).date(byAdding: .day, value: daysOld, to: taken))
        let config = ProjectConfig(bundleID: "com.example.MyApp", keyID: "ABC123", issuerID: "issuer")
        let product = Product(productID: "com.example.pro", kind: "auto_renewable_subscription")
        return Validator(config: config).validateProvenance(of: Self.curve, product: product, path: "p", now: now)
    }

    @Test func aDayParsesToMidnightInUTC() {
        #expect(CalendarDay.date(from: "2026-09-01")?.timeIntervalSince1970 == 1_788_220_800)
        #expect(CalendarDay.date(from: "not a day") == nil)
    }

    @Test func aDateWritesAsItsUTCDay() throws {
        let date = try #require(CalendarDay.date(from: "2026-09-01"))
        #expect(CalendarDay.string(from: date) == "2026-09-01")
    }

    @Test(arguments: [
        ("2026-03-28", "2026-03-30", 2),
        ("2026-03-29", "2026-03-30", 1),
        ("2026-10-24", "2026-10-26", 2)
    ])
    func daysAcrossADaylightSavingChangeAreWholeDays(from start: String, to end: String, expected: Int) throws {
        let previous = NSTimeZone.default
        NSTimeZone.default = try #require(TimeZone(identifier: "Europe/Bucharest"))
        defer { NSTimeZone.default = previous }

        let startDate = try #require(CalendarDay.date(from: start))
        let endDate = try #require(CalendarDay.date(from: end))
        #expect(CalendarDay.daysBetween(startDate, endDate) == expected)

        let cache = PricePointCache(
            productID: "com.example.pro", readOn: start, baseTerritory: "USA", baseAmount: "1",
            anchors: [:], ladders: [:]
        )
        #expect(cache.daysOld(on: endDate) == expected)
    }

    @Test func provenanceOfExactlyAYearIsStillFresh() throws {
        #expect(try provenanceProblems(daysOld: 365).isEmpty)
    }

    @Test func provenanceOfMoreThanAYearIsReported() throws {
        #expect(try provenanceProblems(daysOld: 366).map(\.kind) == [.curveProceedsDrift])
    }
}
