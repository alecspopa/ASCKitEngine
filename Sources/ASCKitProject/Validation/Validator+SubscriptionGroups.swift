import Foundation

/// What is wrong with a subscription group's words.
///
/// App Store Connect needs a display name in at least one language before a
/// subscription in the group can go to review. The custom app name is optional
/// in every language.
extension Validator {
    func validateSubscriptionGroups(_ catalog: ProductCatalog) -> [Problem] {
        var problems: [Problem] = []

        for (name, reason) in catalog.unreadableGroups.sorted(by: { $0.key < $1.key }) {
            problems.append(Problem(
                severity: .error,
                area: .products,
                message: LocalizedStringResource("\(name).json could not be read. \(reason)", bundle: .here),
                fix: LocalizedStringResource("Fix the JSON, or take the file out.", bundle: .here),
                subscriptionGroup: name,
                path: groupPath(for: name),
                kind: .groupFileUnreadable
            ))
        }

        for name in catalog.groupNames where catalog.unreadableGroups[name] == nil {
            let group = catalog.groups[name] ?? SubscriptionGroup(referenceName: name)
            problems += validate(group)
        }

        return problems
    }

    private func validate(_ group: SubscriptionGroup) -> [Problem] {
        let filePath = groupPath(for: group.referenceName)
        let named = group.localizations.values.contains { $0.name?.isEmpty == false }

        // A warning, because the store can already hold the words this file
        // does not.
        guard named else {
            return [Problem(
                severity: .warning,
                area: .products,
                message: LocalizedStringResource("""
                The subscription group \(group.referenceName) has no display name in \
                any language.
                """, bundle: .here),
                fix: LocalizedStringResource("""
                Write a display name in at least one language. App Store Connect does \
                not take a subscription for review without it.
                """, bundle: .here),
                subscriptionGroup: group.referenceName,
                path: filePath,
                kind: .groupHasNoWords
            )]
        }

        var problems: [Problem] = []

        for locale in group.localizations.keys.sorted() where config.writtenLocales.contains(locale) == false {
            problems.append(Problem(
                severity: .warning,
                area: .products,
                message: LocalizedStringResource("""
                The subscription group \(group.referenceName) holds \(locale), which this \
                project does not ship.
                """, bundle: .here),
                fix: LocalizedStringResource("Add \(locale) to locales, or take it out of the group.", bundle: .here),
                locale: locale,
                subscriptionGroup: group.referenceName,
                path: filePath,
                kind: .groupLocaleNotShipped
            ))
        }

        for locale in config.writtenLocales {
            let written = group.localizations[locale]

            for field in GroupField.allCases {
                guard let value = written?[field] else {
                    guard field.isRequired else { continue }
                    problems.append(Problem(
                        severity: .warning,
                        area: .products,
                        message: LocalizedStringResource("""
                        The subscription group \(group.referenceName) has no display name \
                        in \(locale).
                        """, bundle: .here),
                        fix: LocalizedStringResource("""
                        Write one, or the store shows this language the group's name from \
                        another language.
                        """, bundle: .here),
                        locale: locale,
                        subscriptionGroup: group.referenceName,
                        groupField: field,
                        path: filePath,
                        kind: .groupTextNotTranslated
                    ))
                    continue
                }

                problems += validate(field, value: value, locale: locale, group: group)
            }
        }

        return problems
    }

    private func validate(
        _ field: GroupField,
        value: String,
        locale: String,
        group: SubscriptionGroup
    ) -> [Problem] {
        let filePath = groupPath(for: group.referenceName)

        if value.isEmpty {
            // An empty custom app name means the app's own name.
            guard field.isRequired else { return [] }
            return [Problem(
                severity: .error,
                area: .products,
                message: LocalizedStringResource("\(field.rawValue) is empty in \(locale).", bundle: .here),
                fix: LocalizedStringResource("""
                Write a display name, or take the language out of the group file.
                """, bundle: .here),
                locale: locale,
                subscriptionGroup: group.referenceName,
                groupField: field,
                path: filePath,
                kind: .groupTextEmpty
            )]
        }

        var problems: [Problem] = []

        let length = field.length(of: value)
        if length > field.maximumLength {
            problems.append(Problem(
                severity: .error,
                area: .products,
                message: LocalizedStringResource("""
                \(field.rawValue) is \(length) characters in \(locale), and the \
                limit is \(field.maximumLength).
                """, bundle: .here),
                fix: LocalizedStringResource("Cut \(length - field.maximumLength) characters.", bundle: .here),
                locale: locale,
                subscriptionGroup: group.referenceName,
                groupField: field,
                path: filePath,
                kind: .groupTextOverLimit
            ))
        }

        if value.trimmingCharacters(in: .whitespacesAndNewlines) != value {
            problems.append(Problem(
                severity: .warning,
                area: .products,
                message: LocalizedStringResource("\(field.rawValue) in \(locale) starts or ends with a space.", bundle: .here),
                fix: LocalizedStringResource("Trim it. App Store Connect keeps the space and counts it.", bundle: .here),
                locale: locale,
                subscriptionGroup: group.referenceName,
                groupField: field,
                path: filePath,
                kind: .groupTextHasEdgeSpace
            ))
        }

        return problems
    }

    func groupPath(for name: String) -> String {
        "\(config.productsPath)/\(ProductStore.groupsFolderName)/\(name).json"
    }
}
