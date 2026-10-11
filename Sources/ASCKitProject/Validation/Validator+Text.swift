import Foundation

extension Validator {
    /// The rules of one rule set for words, by kind.
    struct WordRules {
        let empty: Problem.Kind
        let overLimit: Problem.Kind
        let edgeSpace: Problem.Kind
        /// What to do about an empty value.
        let emptyFix: LocalizedStringResource
    }

    /// The checks that the words of a product and of a subscription group
    /// share: empty, over the limit, and a space at either end.
    ///
    /// `problem` makes one problem, so each caller names its own product or
    /// group and its own field.
    func validateWords(
        name: String,
        value: String,
        length: Int,
        maximum: Int,
        locale: String,
        rules: WordRules,
        problem: (Problem.Severity, Problem.Kind, LocalizedStringResource, LocalizedStringResource) -> Problem
    ) -> [Problem] {
        if value.isEmpty {
            return [problem(
                .error, rules.empty,
                LocalizedStringResource("\(name) is empty in \(locale).", bundle: .here),
                rules.emptyFix
            )]
        }

        var problems: [Problem] = []
        if length > maximum {
            problems.append(problem(
                .error, rules.overLimit,
                LocalizedStringResource("""
                \(name) is \(length) characters in \(locale), and the \
                limit is \(maximum).
                """, bundle: .here),
                LocalizedStringResource("Cut \(length - maximum) characters.", bundle: .here)
            ))
        }
        if value.trimmingCharacters(in: .whitespacesAndNewlines) != value {
            problems.append(problem(
                .warning, rules.edgeSpace,
                LocalizedStringResource("\(name) in \(locale) starts or ends with a space.", bundle: .here),
                LocalizedStringResource("Trim it. App Store Connect keeps the space and counts it.", bundle: .here)
            ))
        }
        return problems
    }
}
