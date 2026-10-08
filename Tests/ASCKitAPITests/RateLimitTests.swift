import ASCKitTestSupport
import Foundation
import Testing
@testable import ASCKitAPI

struct RateLimitTests {
    func response(_ headers: [String: String]) throws -> HTTPURLResponse {
        try #require(HTTPURLResponse(
            url: URL(string: "https://api.example.test/v1/apps")!,
            statusCode: 429,
            httpVersion: "HTTP/1.1",
            headerFields: headers
        ))
    }

    // MARK: - What is left of the hour

    @Test func readsTheCountsOutOfApplesHeader() {
        let limit = RateLimit(headerValue: "user-hour-lim:3500;user-hour-rem:500;")

        #expect(limit?.limitPerHour == 3500)
        #expect(limit?.remainingThisHour == 500)
        #expect(limit?.retryAfter == nil)
    }

    @Test func readsNothingOutOfAHeaderItDoesNotUnderstand() {
        #expect(RateLimit(headerValue: "nothing-here") == nil)
    }

    // MARK: - How long to wait

    @Test func readsAWaitGivenInSeconds() throws {
        let limit = try RateLimit(response: response(["Retry-After": "90"]))

        #expect(limit?.retryAfter == .seconds(90))
    }

    @Test func readsAWaitGivenAsADate() throws {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "GMT")
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss zzz"
        let header = formatter.string(from: Date(timeIntervalSinceNow: 300))

        let limit = try RateLimit(response: response(["Retry-After": header]))
        let wait = try #require(limit?.retryAfter)

        #expect(wait > .seconds(240))
        #expect(wait <= .seconds(300))
    }

    /// A date already gone by means wait no longer, not wait backwards.
    @Test func readsADateInThePastAsNoWaitAtAll() throws {
        let limit = try RateLimit(response: response(["Retry-After": "Wed, 21 Oct 2015 07:28:00 GMT"]))

        #expect(limit?.retryAfter == .zero)
    }

    @Test func keepsTheWaitWhenThereAreNoCounts() throws {
        let limit = try RateLimit(response: response(["Retry-After": "30"]))

        #expect(limit?.retryAfter == .seconds(30))
        #expect(limit?.remainingThisHour == nil)
    }

    @Test func keepsBothWhenAppleSendsBoth() throws {
        let limit = try RateLimit(response: response([
            "X-Rate-Limit": "user-hour-lim:3500;user-hour-rem:0;",
            "Retry-After": "60"
        ]))

        #expect(limit?.remainingThisHour == 0)
        #expect(limit?.retryAfter == .seconds(60))
    }

    @Test func findsNothingInAResponseWithNeitherHeader() throws {
        #expect(try RateLimit(response: response([:])) == nil)
    }

    // MARK: - Saying it in words

    @Test(arguments: [
        (Duration.seconds(1), "1 second"),
        (.seconds(45), "45 seconds"),
        (.seconds(120), "2 minutes"),
        (.seconds(600), "10 minutes"),
        (.seconds(7200), "2 hours"),
        (.milliseconds(200), "a moment")
    ])
    func spellsOutAWait(_ wait: Duration, _ expected: String) {
        #expect(ErrorMessage.spellOut(wait) == expected)
    }

    // MARK: - What a person reads

    @Test func namesTheWaitInTheMessage() {
        let limit = RateLimit(limitPerHour: 3500, remainingThisHour: 0, retryAfter: .seconds(600))
        let error = ASCError.rateLimited(rateLimit: limit, details: [])

        #expect(error.description == "Too many requests to App Store Connect. It says to try again in 10 minutes.")
    }

    @Test func fallsBackToWhatIsLeftOfTheHour() {
        let limit = RateLimit(limitPerHour: 3500, remainingThisHour: 0)
        let error = ASCError.rateLimited(rateLimit: limit, details: [])

        #expect(error.description == "Too many requests to App Store Connect. 0 requests left this hour.")
    }

    @Test func saysOnlyWhatItKnows() {
        let error = ASCError.rateLimited(rateLimit: nil, details: [])

        #expect(error.description == "Too many requests to App Store Connect.")
    }
}
