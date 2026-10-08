import Foundation
import Testing
@testable import ASCKitAPI

struct ErrorMessageTests {
    /// The dump names a session task and a URL and helps nobody. This is what
    /// a person saw in an alert before there was anything else to show them.
    @Test func saysWhatANetworkFailureWasInWords() {
        let text = ErrorMessage.text(for: URLError(.notConnectedToInternet))

        #expect(text == "No internet connection, so ASCKit cannot reach App Store Connect.")
        #expect(text.contains("NSURLErrorDomain") == false)
        #expect(text.contains("-1009") == false)
    }

    @Test func explainsANetworkFailureItHasNoSentenceFor() {
        let text = ErrorMessage.text(for: URLError(.unsupportedURL))

        #expect(text.hasPrefix("ASCKit cannot reach App Store Connect. "))
    }

    // MARK: - App Store Connect's refusals

    /// Apple sends details for most refusals and none for some. A sentence
    /// that waited for them to close it ended with no full stop.
    @Test(arguments: [
        ASCError.notAnHTTPResponse,
        .unauthorized(details: []),
        .unauthorizedIndividualKey(details: []),
        .forbidden(details: []),
        .notFound(details: []),
        .conflict(details: []),
        .unprocessable(details: []),
        .rateLimited(rateLimit: nil, details: []),
        .serverError(status: 500, details: []),
        .unexpectedStatus(status: 418, details: [], body: Data())
    ])
    func endsEveryRefusalWithAFullStop(_ error: ASCError) {
        #expect(error.description.hasSuffix("."))
    }

    @Test func putsApplesWordsInASentenceOfTheirOwn() {
        let error = ASCError.conflict(details: [
            ASCErrorDetail(code: "STATE_ERROR", detail: "This version cannot be edited", pointer: "/data/attributes/whatsNew")
        ])

        #expect(error.description.hasSuffix("""
        App Store Connect said: This version cannot be edited. The field is /data/attributes/whatsNew.
        """))
    }

    @Test func namesTheFieldADecoderStoppedAtAndNotItsDump() throws {
        struct Answer: Decodable { let name: String }
        let thrown = try #require(throws: DecodingError.self) {
            try JSONDecoder().decode(Answer.self, from: Data(#"{"name": 7}"#.utf8))
        }

        let text = ASCError.decodingFailed(underlying: thrown, body: Data()).description

        #expect(text.contains("The field name is not what ASCKit expects."))
        #expect(text.contains("typeMismatch") == false)
    }

    @Test func keepsTheWordsAnErrorWroteForItself() {
        let error = ASCError.forbidden(details: [])

        #expect(ErrorMessage.text(for: error) == error.description)
    }

    @Test func readsTheSentenceOutOfAFileError() {
        let text = ErrorMessage.text(for: CocoaError(.fileNoSuchFile))

        #expect(text.contains("NSCocoaErrorDomain") == false)
        #expect(text.isEmpty == false)
    }

    // MARK: - Telling a stop from a failure

    @Test func countsBothShapesOfCancellationAsOne() {
        #expect(CancellationError().isCancellation)
        #expect(URLError(.cancelled).isCancellation)
        #expect(URLError(.timedOut).isCancellation == false)
        #expect(ASCError.forbidden(details: []).isCancellation == false)
    }

    /// Cancelling the others is what one failure does, so a cancellation is
    /// the effect and the failure beside it is the reason.
    @Test func picksTheFailureOverTheCancellationsItCaused() throws {
        let errors: [any Error] = [
            URLError(.cancelled),
            ASCError.rateLimited(rateLimit: nil, details: []),
            CancellationError()
        ]

        let picked = try #require(errors.mostTelling)
        #expect(picked.isCancellation == false)
    }

    @Test func picksACancellationWhenThatIsAllThereIs() throws {
        let errors: [any Error] = [CancellationError(), URLError(.cancelled)]

        #expect(try #require(errors.mostTelling).isCancellation)
    }

    @Test func picksNothingOutOfNothing() {
        #expect(([] as [any Error]).mostTelling == nil)
    }
}
