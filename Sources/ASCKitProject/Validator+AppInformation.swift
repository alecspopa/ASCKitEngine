import Foundation

/// Everything the listing text can be wrong about.
extension Validator {
    func validateCopy(_ content: VersionContent) -> [Problem] {
        var problems: [Problem] = []
        let source = content.appInformation[config.sourceLocale]

        for locale in config.writtenLocales.sorted() {
            guard let copy = content.appInformation[locale] else { continue }
            let path = informationPath(content, locale)

            problems += validateFields(copy, locale: locale, path: path)
            problems += validateRequiredFields(copy, locale: locale, path: path, source: source)
            problems += validateTranslation(copy, locale: locale, path: path, source: source)
            problems += validateStatus(copy, locale: locale, path: path)
        }
        return problems
    }

    /// The fields App Store Connect refuses a submission without, and the
    /// fields this language has no words for.
    ///
    /// Checked here rather than found out at submission time, which is the
    /// slowest possible way to learn that a support URL is missing.
    ///
    /// A field the source language fills and this one leaves empty is marked,
    /// so the language page can say what is still to be written. Web addresses
    /// are left out of that: the same address in every language is the answer
    /// rather than the problem.
    func validateRequiredFields(
        _ copy: AppInformation,
        locale: String,
        path: String,
        source: AppInformation?
    ) -> [Problem] {
        var problems: [Problem] = []
        let isSource = locale == config.sourceLocale

        for field in MetadataField.allCases {
            let value = copy.fields[field]?.trimmingCharacters(in: .whitespacesAndNewlines)
            guard value?.isEmpty != false else { continue }

            let sourceHasWords = isSource == false
                && field.isURL == false
                && source?.fields[field]?.isEmpty == false
            let kind: Problem.Kind = sourceHasWords ? .textNotTranslated : .textMissing

            switch field.requirement {
            case .always:
                problems.append(missing(field, locale: locale, path: path, kind: kind))
            case .sourceLanguageOnly where isSource:
                problems.append(missing(field, locale: locale, path: path, kind: .textMissing))
            case .afterTheFirstVersion:
                problems.append(Problem(
                    severity: .warning,
                    area: .appInformation,
                    message: LocalizedStringResource("\(locale) has no whatsNew.", bundle: .here),
                    fix: LocalizedStringResource("""
                    Apple needs it for every version except the app's first. \
                    Leave it out only if this is the first.
                    """, bundle: .here),
                    locale: locale,
                    field: field,
                    path: path,
                    kind: kind
                ))
            case .never:
                guard sourceHasWords else { continue }
                problems.append(Problem(
                    severity: .warning,
                    area: .appInformation,
                    message: LocalizedStringResource("\(locale) has no \(field.rawValue).", bundle: .here),
                    fix: LocalizedStringResource("""
                    \(config.sourceLocale) has one. Write the \(locale) words, or leave \
                    the field out on purpose.
                    """, bundle: .here),
                    locale: locale,
                    field: field,
                    path: path,
                    kind: .textNotTranslated
                ))
            case .sourceLanguageOnly:
                continue
            }
        }
        return problems
    }

    private func missing(
        _ field: MetadataField,
        locale: String,
        path: String,
        kind: Problem.Kind
    ) -> Problem {
        Problem(
            severity: .error,
            area: .appInformation,
            message: LocalizedStringResource("\(locale) has no \(field.rawValue).", bundle: .here),
            fix: LocalizedStringResource("App Store Connect refuses a submission without it.", bundle: .here),
            locale: locale,
            field: field,
            path: path,
            kind: kind
        )
    }

    private func validateFields(_ copy: AppInformation, locale: String, path: String) -> [Problem] {
        var problems: [Problem] = []

        for field in copy.fields.presentFields {
            guard let value = copy.fields[field] else { continue }

            if value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                problems.append(Problem(
                    severity: .error,
                    area: .appInformation,
                    message: LocalizedStringResource("\(field.rawValue) is empty.", bundle: .here),
                    fix: LocalizedStringResource(
                        "An empty value blanks the field on the store. Remove the field to leave it alone.",
                        bundle: .here
                    ),
                    locale: locale,
                    field: field,
                    path: path,
                    kind: .textEmpty
                ))
                continue
            }

            let length = field.length(of: value)

            if let maximum = field.maximumLength, length > maximum {
                problems.append(Problem(
                    severity: .error,
                    area: .appInformation,
                    message: LocalizedStringResource(
                        "\(field.rawValue) is \(length) characters, and the limit is \(maximum).",
                        bundle: .here
                    ),
                    fix: LocalizedStringResource("Cut \(length - maximum) characters.", bundle: .here),
                    locale: locale,
                    field: field,
                    path: path,
                    kind: .textOverLimit
                ))
            }

            if let minimum = field.minimumLength, length < minimum {
                problems.append(Problem(
                    severity: .error,
                    area: .appInformation,
                    message: LocalizedStringResource(
                        "\(field.rawValue) is \(length) characters, and the minimum is \(minimum).",
                        bundle: .here
                    ),
                    locale: locale,
                    field: field,
                    path: path,
                    kind: .textUnderMinimum
                ))
            }

            problems += validateShape(field, value: value, locale: locale, path: path)
        }

        return problems
    }

    /// Rules that are about the shape of a value rather than its length.
    private func validateShape(
        _ field: MetadataField,
        value: String,
        locale: String,
        path: String
    ) -> [Problem] {
        var problems: [Problem] = []

        if field == .keywords, value.contains(", ") {
            problems.append(Problem(
                severity: .warning,
                area: .appInformation,
                message: LocalizedStringResource("keywords has a space after a comma.", bundle: .here),
                fix: LocalizedStringResource("Every space costs a character of the 100. Separate with commas alone.", bundle: .here),
                locale: locale,
                field: field,
                path: path,
                kind: .keywordsHaveSpace
            ))
        }

        if field.isURL {
            let url = URL(string: value)
            if url?.scheme?.lowercased() != "https" {
                problems.append(Problem(
                    severity: .error,
                    area: .appInformation,
                    message: LocalizedStringResource("\(field.rawValue) is not an https address.", bundle: .here),
                    locale: locale,
                    field: field,
                    path: path,
                    kind: .urlNotHTTPS
                ))
            }
        }

        if value != value.trimmingCharacters(in: .whitespacesAndNewlines) {
            problems.append(Problem(
                severity: .warning,
                area: .appInformation,
                message: LocalizedStringResource("\(field.rawValue) starts or ends with a space.", bundle: .here),
                fix: LocalizedStringResource("The space is published as written, and it counts against the limit.", bundle: .here),
                locale: locale,
                field: field,
                path: path,
                kind: .textHasEdgeSpace
            ))
        }

        return problems
    }

    private func validateStatus(
        _ copy: AppInformation,
        locale: String,
        path: String
    ) -> [Problem] {
        var problems: [Problem] = []

        if copy.status.canPublish == false {
            problems.append(Problem(
                severity: .warning,
                area: .appInformation,
                message: LocalizedStringResource(
                    "\(locale) is marked \(copy.status.rawValue), so it will not be published.",
                    bundle: .here
                ),
                fix: LocalizedStringResource("Read it, then set status to approved, or ai_approved if a machine wrote it.", bundle: .here),
                locale: locale,
                path: path,
                kind: .statusNotPublishable
            ))
        }

        return problems
    }

    /// Text this language took from the source language word for word.
    ///
    /// `ProjectConfig.warnsAboutCopiedText` decides which language and which
    /// field this is worth saying about. The in-app purchases ask the same
    /// rule, so `textMatchesSource` and `productTextMatchesSource` appear for
    /// the same reason.
    private func validateTranslation(
        _ copy: AppInformation,
        locale: String,
        path: String,
        source: AppInformation?
    ) -> [Problem] {
        guard locale != config.sourceLocale, let source else { return [] }

        let fields = copy.fields.matchingTextFields(in: source.fields).filter {
            config.warnsAboutCopiedText($0, in: locale)
        }

        return fields.map { field in
            Problem(
                severity: .warning,
                area: .appInformation,
                message: LocalizedStringResource("\(locale) \(field.rawValue) matches \(config.sourceLocale).", bundle: .here),
                fix: LocalizedStringResource(
                    "Translate \(field.displayName), or silence this warning if the shared text is intentional.",
                    bundle: .here
                ),
                locale: locale,
                field: field,
                path: path,
                kind: .textMatchesSource
            )
        }
    }
}

private extension AppInformation.Fields {
    /// Fields this language holds, that read the same as the source language's.
    /// Whether that is worth a warning is the config's answer, not this one's.
    func matchingTextFields(in source: Self) -> [MetadataField] {
        MetadataField.allCases.filter {
            self[$0]?.isEmpty == false && self[$0] == source[$0]
        }
    }
}
