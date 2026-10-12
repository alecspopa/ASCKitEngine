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

    /// One field's words in one language, and what they are measured against.
    struct Words {
        let name: String
        let value: String
        let length: Int
        let maximum: Int
        let locale: String
    }

    /// The checks that the words of a product and of a subscription group
    /// share: empty, over the limit, and a space at either end.
    ///
    /// `problem` makes one problem, so each caller names its own product or
    /// group and its own field.
    func validateWords(
        _ words: Words,
        rules: WordRules,
        problem: (Problem.Severity, Problem.Kind, LocalizedStringResource, LocalizedStringResource) -> Problem
    ) -> [Problem] {
        if words.value.isEmpty {
            return [problem(
                .error, rules.empty,
                LocalizedStringResource("\(words.name) is empty in \(words.locale).", bundle: .here),
                rules.emptyFix
            )]
        }

        var problems: [Problem] = []
        if words.length > words.maximum {
            problems.append(problem(
                .error, rules.overLimit,
                LocalizedStringResource("""
                \(words.name) is \(words.length) characters in \(words.locale), and the \
                limit is \(words.maximum).
                """, bundle: .here),
                LocalizedStringResource("Cut \(words.length - words.maximum) characters.", bundle: .here)
            ))
        }
        if words.value.trimmingCharacters(in: .whitespacesAndNewlines) != words.value {
            problems.append(problem(
                .warning, rules.edgeSpace,
                LocalizedStringResource("\(words.name) in \(words.locale) starts or ends with a space.", bundle: .here),
                LocalizedStringResource("Trim it. App Store Connect keeps the space and counts it.", bundle: .here)
            ))
        }
        return problems
    }
}
