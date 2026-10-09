import Foundation

/// What is wrong with an in-app purchase's words.
///
/// Both fields are needed in every language. App Store Connect will not take a
/// purchase with either one missing, and the store shows the name next to the
/// price everywhere, so a half-translated product is a listing gap a buyer
/// sees.
extension Validator {
    func validateProducts(_ catalog: ProductCatalog) -> [Problem] {
        var problems: [Problem] = []

        for (name, reason) in catalog.unreadable.sorted(by: { $0.key < $1.key }) {
            problems.append(Problem(
                severity: .error,
                area: .products,
                message: LocalizedStringResource("\(name).json could not be read. \(reason)", bundle: .here),
                fix: LocalizedStringResource("Fix the JSON, or take the file out.", bundle: .here),
                productID: name,
                path: path(for: name),
                kind: .productFileUnreadable
            ))
        }

        for (name, written) in catalog.misnamed.sorted(by: { $0.key < $1.key }) {
            problems.append(Problem(
                severity: .warning,
                area: .products,
                message: LocalizedStringResource("""
                \(name).json says its product is \(written). The file name is what \
                ASCKit uses.
                """, bundle: .here),
                fix: LocalizedStringResource("Rename the file to \(written).json, or change productId to \(name).", bundle: .here),
                productID: name,
                path: path(for: name),
                kind: .productIDMismatch
            ))
        }

        for product in catalog.sorted {
            problems += validate(product)
        }

        return problems
    }

    private func validate(_ product: Product) -> [Problem] {
        var problems = validateKind(product)
        problems += validateReviewNote(product)
        problems += validateLocalizations(product)
        problems += validateTranslations(product)
        return problems
    }

    // MARK: - What kind of purchase it is

    private func validateKind(_ product: Product) -> [Problem] {
        let filePath = path(for: product.productID)

        guard let kind = product.resolvedKind else {
            return [Problem(
                severity: .error,
                area: .products,
                message: LocalizedStringResource("\(product.kind) is not a kind of in-app purchase ASCKit knows.", bundle: .here),
                fix: LocalizedStringResource("Use one of: \(Product.Kind.allIdentifiers.joined(separator: ", ")).", bundle: .here),
                productID: product.productID,
                path: filePath,
                kind: .productKindNotKnown
            )]
        }

        var problems: [Problem] = []

        // The group decides where a subscription sits against its siblings, and
        // an upgrade only works within one. There is nowhere to put a one-time
        // purchase.
        if kind.isAutoRenewable, product.subscriptionGroup?.isEmpty ?? true {
            problems.append(Problem(
                severity: .error,
                area: .products,
                message: LocalizedStringResource("\(product.productID) is a subscription with no group.", bundle: .here),
                fix: LocalizedStringResource("Add subscriptionGroup. Every auto-renewable subscription belongs to one.", bundle: .here),
                productID: product.productID,
                path: filePath,
                kind: .subscriptionHasNoGroup
            ))
        }

        if kind.isAutoRenewable == false, product.subscriptionGroup != nil {
            problems.append(Problem(
                severity: .error,
                area: .products,
                message: LocalizedStringResource(
                    "\(product.productID) names a subscription group.", bundle: .here
                ),
                fix: LocalizedStringResource("Take subscriptionGroup out. Only an auto-renewable subscription has one.", bundle: .here),
                productID: product.productID,
                path: filePath,
                kind: .nonSubscriptionNamesGroup
            ))
        }

        if kind.isAutoRenewable == false, product.price?.preserveCurrentPrice != nil {
            problems.append(Problem(
                severity: .error,
                area: .products,
                message: LocalizedStringResource(
                    "\(product.productID) sets preserveCurrentPrice.", bundle: .here
                ),
                fix: LocalizedStringResource("Take it out. Only a subscription has customers who already pay.", bundle: .here),
                productID: product.productID,
                path: filePath,
                kind: .nonSubscriptionPreservesPrice
            ))
        }

        if kind.isAutoRenewable, product.subscriptionPeriod?.isEmpty ?? true {
            problems.append(Problem(
                severity: .warning,
                area: .products,
                message: LocalizedStringResource("""
                \(product.productID) is a subscription and does not say how long a \
                period is.
                """, bundle: .here),
                fix: LocalizedStringResource("""
                Add subscriptionPeriod, such as ONE_MONTH. ASCKit never writes it, and \
                recording it lets a pull say when the store and the file disagree.
                """, bundle: .here),
                productID: product.productID,
                path: filePath,
                kind: .subscriptionHasNoPeriod
            ))
        }

        return problems
    }

    // MARK: - The note for App Review

    private func validateReviewNote(_ product: Product) -> [Problem] {
        guard let note = product.reviewNote else { return [] }
        guard note.count > ProductField.reviewNoteCharacters else { return [] }
        return [Problem(
            severity: .error,
            area: .products,
            message: LocalizedStringResource("The review note is \(note.count) characters, and the limit is 4000.", bundle: .here),
            fix: LocalizedStringResource("Cut \(note.count - ProductField.reviewNoteCharacters) characters.", bundle: .here),
            productID: product.productID,
            path: path(for: product.productID),
            kind: .reviewNoteOverLimit
        )]
    }

    // MARK: - The words a buyer reads

    private func validateLocalizations(_ product: Product) -> [Problem] {
        var problems: [Problem] = []
        let filePath = path(for: product.productID)

        let strays = product.localizations.keys.sorted()
            .filter { config.writtenLocales.contains($0) == false }
        for locale in strays {
            problems.append(Problem(
                severity: .warning,
                area: .products,
                message: LocalizedStringResource("\(product.productID) holds \(locale), which this project does not ship.", bundle: .here),
                fix: LocalizedStringResource("Add \(locale) to locales, or take it out of the product.", bundle: .here),
                locale: locale,
                productID: product.productID,
                path: filePath,
                kind: .productLocaleNotShipped
            ))
        }

        for locale in config.writtenLocales {
            let written = product.localizations[locale]

            for field in ProductField.allCases {
                guard let value = written?[field] else {
                    // Only worth saying once the product has words in it at all.
                    // A product nobody has started on is a draft, not a gap.
                    if product.localizations.isEmpty == false {
                        problems.append(Problem(
                            severity: product.status.canPublish ? .error : .warning,
                            area: .products,
                            message: LocalizedStringResource("\(product.productID) has no \(field.rawValue) in \(locale).", bundle: .here),
                            fix: LocalizedStringResource("""
                            App Store Connect needs both a name and a description in \
                            every language.
                            """, bundle: .here),
                            locale: locale,
                            productID: product.productID,
                            productField: field,
                            path: filePath,
                            kind: .productTextNotTranslated
                        ))
                    }
                    continue
                }

                problems += validate(field, value: value, locale: locale, product: product)
            }
        }

        return problems
    }

    /// Words that are the source language's, character for character.
    ///
    /// A warning rather than an error, and one that can be silenced. Somebody
    /// who means the same words in both languages silences it once and is not
    /// asked again.
    ///
    /// `ProjectConfig.warnsAboutCopiedText` decides which language and which
    /// field this is worth saying about. The listing asks the same rule, so
    /// `productTextMatchesSource` and `textMatchesSource` appear for the same
    /// reason.
    private func validateTranslations(_ product: Product) -> [Problem] {
        guard let source = product.localizations[config.sourceLocale] else { return [] }

        var problems: [Problem] = []

        for locale in config.writtenLocales where locale != config.sourceLocale {
            guard let written = product.localizations[locale] else { continue }

            for field in ProductField.allCases {
                guard config.warnsAboutCopiedText(field, in: locale) else { continue }
                guard let value = written[field], value.isEmpty == false else { continue }
                guard value == source[field] else { continue }

                problems.append(Problem(
                    severity: .warning,
                    area: .products,
                    message: LocalizedStringResource("""
                    \(product.productID) \(field.rawValue) in \(locale) matches \
                    \(config.sourceLocale).
                    """, bundle: .here),
                    fix: LocalizedStringResource("""
                    Translate \(field.displayName), or silence this warning if the same \
                    words in both languages are meant.
                    """, bundle: .here),
                    locale: locale,
                    productID: product.productID,
                    productField: field,
                    path: path(for: product.productID),
                    kind: .productTextMatchesSource
                ))
            }
        }

        return problems
    }

    private func validate(
        _ field: ProductField,
        value: String,
        locale: String,
        product: Product
    ) -> [Problem] {
        var problems: [Problem] = []
        let filePath = path(for: product.productID)

        if value.isEmpty {
            problems.append(Problem(
                severity: .error,
                area: .products,
                message: LocalizedStringResource("\(field.rawValue) is empty in \(locale).", bundle: .here),
                fix: LocalizedStringResource("""
                App Store Connect needs both fields. Write something, or take the \
                language out of the file.
                """, bundle: .here),
                locale: locale,
                productID: product.productID,
                productField: field,
                path: filePath,
                kind: .productTextEmpty
            ))
            return problems
        }

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
                productID: product.productID,
                productField: field,
                path: filePath,
                kind: .productTextOverLimit
            ))
        }

        if value.trimmingCharacters(in: .whitespacesAndNewlines) != value {
            problems.append(Problem(
                severity: .warning,
                area: .products,
                message: LocalizedStringResource("\(field.rawValue) in \(locale) starts or ends with a space.", bundle: .here),
                fix: LocalizedStringResource("Trim it. App Store Connect keeps the space and counts it.", bundle: .here),
                locale: locale,
                productID: product.productID,
                productField: field,
                path: filePath,
                kind: .productTextHasEdgeSpace
            ))
        }

        return problems
    }

    func path(for productID: String) -> String {
        "\(config.productsPath)/\(productID).json"
    }
}
