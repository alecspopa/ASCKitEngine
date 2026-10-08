import Foundation

/// Turns problems into text. Lives in the library rather than in the command
/// line tool, so the wording is testable and the app can use the same summary.
public enum ProblemFormatter {
    /// `path: severity: message fix`, which is the shape compilers print and
    /// therefore the shape editors and terminals already make clickable.
    ///
    /// The resources are resolved here, because a line goes to a terminal and a
    /// terminal takes text.
    public static func line(for problem: Problem, rootURL: URL?) -> String {
        var text = ""

        if let path = problem.path {
            let full = rootURL.map { $0.appending(path: path).path } ?? path
            text += "\(full): "
        }
        text += "\(problem.severity.rawValue): "

        let message = String(localized: problem.message)

        // The language is worth naming, but not twice.
        if let locale = problem.locale, message.contains(locale) == false {
            text += "[\(locale)] "
        }
        text += message

        if let fix = problem.fix {
            text += " \(String(localized: fix))"
        }
        return text
    }

    /// One line saying how bad it is, and whether that blocks publishing.
    ///
    /// A silenced warning is counted out loud rather than left out. Somebody
    /// reading "nothing wrong" should not have to remember what they hid.
    ///
    /// Each count is its own catalog entry, so the string catalog holds the
    /// plural rule for the language the reader has.
    public static func summary(_ problems: [Problem], silenced: Int = 0) -> String {
        let errors = problems.errors.count
        let warnings = problems.warnings.count
        let hidden = silenced > 0
            ? " " + String(localized: "\(silenced) silenced.", bundle: .module)
            : ""

        guard errors > 0 || warnings > 0 else {
            return String(localized: "Nothing wrong.", bundle: .module) + hidden
        }

        var parts: [String] = []
        if errors > 0 {
            parts.append(String(localized: "\(errors) errors", bundle: .module))
        }
        if warnings > 0 {
            parts.append(String(localized: "\(warnings) warnings", bundle: .module))
        }

        let counted = parts.joined(separator: ", ")
        guard errors > 0 else { return "\(counted).\(hidden)" }
        return "\(counted). " + String(localized: "Not ready to publish.", bundle: .module) + hidden
    }
}
