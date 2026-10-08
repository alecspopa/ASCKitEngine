import Foundation
import Testing
@testable import ASCKitProject

struct ProblemFormatterTests {
    let root = URL(fileURLWithPath: "/projects/demo/appstore")

    func problem(
        severity: Problem.Severity = .error,
        message: LocalizedStringResource = "subtitle is 46 characters, and the limit is 30.",
        fix: LocalizedStringResource? = nil,
        locale: String? = nil,
        path: String? = nil,
        kind: Problem.Kind = .textOverLimit
    ) -> Problem {
        Problem(
            severity: severity,
            area: .appInformation,
            message: message,
            fix: fix,
            locale: locale,
            path: path,
            kind: kind
        )
    }

    /// The shape compilers print, so editors and terminals make it clickable.
    @Test func writesTheFullPathThenTheSeverityThenTheMessage() {
        let text = ProblemFormatter.line(
            for: problem(path: "versions/1.0/copy/de-DE.json"),
            rootURL: root
        )
        #expect(text == "/projects/demo/appstore/versions/1.0/copy/de-DE.json: "
            + "error: subtitle is 46 characters, and the limit is 30.")
    }

    @Test func namesTheLanguageWhenTheMessageDoesNot() {
        let text = ProblemFormatter.line(for: problem(locale: "de-DE"), rootURL: nil)
        #expect(text == "error: [de-DE] subtitle is 46 characters, and the limit is 30.")
    }

    /// Naming it twice reads as a stutter.
    @Test func doesNotNameTheLanguageTwice() {
        let text = ProblemFormatter.line(
            for: problem(message: "de-DE is marked draft.", locale: "de-DE"),
            rootURL: nil
        )
        #expect(text == "error: de-DE is marked draft.")
    }

    @Test func putsTheFixAfterTheMessage() {
        let text = ProblemFormatter.line(
            for: problem(fix: "Cut 16 characters."),
            rootURL: nil
        )
        #expect(text.hasSuffix("and the limit is 30. Cut 16 characters."))
    }

    @Test func leavesThePathAloneWhenThereIsNoRoot() {
        let text = ProblemFormatter.line(for: problem(path: "asckit.json"), rootURL: nil)
        #expect(text.hasPrefix("asckit.json: error: "))
    }

    // MARK: - The summary

    @Test func saysNothingIsWrongWhenNothingIs() {
        #expect(ProblemFormatter.summary([]) == "Nothing wrong.")
    }

    /// The noun's ending comes from the string catalog's plural rule, so the
    /// test reads the count and the verdict rather than the last letter.
    @Test func countsErrorsAndWarningsSeparately() {
        let problems = [
            problem(severity: .error),
            problem(severity: .error),
            problem(severity: .warning)
        ]
        let text = ProblemFormatter.summary(problems)
        #expect(text.hasPrefix("2 error"))
        #expect(text.contains("1 warning"))
        #expect(text.hasSuffix("Not ready to publish."))
    }

    @Test func countsOneError() {
        let text = ProblemFormatter.summary([problem()])
        #expect(text.hasPrefix("1 error"))
        #expect(text.hasSuffix("Not ready to publish."))
    }

    /// A warning is worth saying, and it does not stop a publish.
    @Test func doesNotSayNotReadyWhenThereAreOnlyWarnings() {
        let text = ProblemFormatter.summary([problem(severity: .warning)])
        #expect(text.hasPrefix("1 warning"))
        #expect(text.contains("Not ready") == false)
    }
}
