import Foundation

/// What is wrong with a retention message's words and image.
///
/// App Store Connect needs a header and a body in every language the
/// subscription is sold in. The image is optional, one for all languages.
extension Validator {
    func validateRetentionMessages(_ catalog: ProductCatalog) -> [Problem] {
        var problems: [Problem] = []

        for (name, reason) in catalog.unreadableRetentionMessages.sorted(by: { $0.key < $1.key }) {
            problems.append(Problem(
                severity: .error,
                area: .products,
                message: LocalizedStringResource("\(name).json could not be read. \(reason)", bundle: .here),
                fix: LocalizedStringResource("Fix the JSON, or take the file out.", bundle: .here),
                retentionMessage: name,
                path: retentionPath(for: name),
                kind: .retentionFileUnreadable
            ))
        }

        for message in catalog.sortedRetentionMessages {
            problems += validate(message)
            problems += validateRetentionImages(catalog.retentionImages[message.referenceName] ?? [], of: message)
        }
        return problems
    }

    private func validate(_ message: RetentionMessage) -> [Problem] {
        let name = message.referenceName
        let filePath = retentionPath(for: name)

        // A warning, because App Store Connect can already hold the words.
        guard message.localizations.isEmpty == false else {
            return [Problem(
                severity: .warning,
                area: .products,
                message: LocalizedStringResource(
                    "The retention message \(name) has no words in any language.", bundle: .here
                ),
                fix: LocalizedStringResource("Write a header and a body in each language.", bundle: .here),
                retentionMessage: name,
                path: filePath,
                kind: .retentionHasNoWords
            )]
        }

        var problems: [Problem] = []
        for locale in message.localizations.keys.sorted() where config.writtenLocales.contains(locale) == false {
            problems.append(Problem(
                severity: .warning,
                area: .products,
                message: LocalizedStringResource(
                    "The retention message \(name) holds \(locale), which this project does not ship.",
                    bundle: .here
                ),
                fix: LocalizedStringResource("Add \(locale) to locales, or take it out of the message.", bundle: .here),
                locale: locale,
                retentionMessage: name,
                path: filePath,
                kind: .retentionLocaleNotShipped
            ))
        }

        for locale in config.writtenLocales {
            for field in RetentionField.allCases {
                guard let value = message.localizations[locale]?[field] else {
                    problems.append(Problem(
                        severity: .warning,
                        area: .products,
                        message: LocalizedStringResource(
                            "The retention message \(name) has no \(field.displayName) in \(locale).", bundle: .here
                        ),
                        fix: LocalizedStringResource(
                            "Write one. App Store Connect needs every language the subscription is sold in.",
                            bundle: .here
                        ),
                        locale: locale,
                        retentionMessage: name,
                        retentionField: field,
                        path: filePath,
                        kind: .retentionTextNotTranslated
                    ))
                    continue
                }
                problems += validateWords(
                    Words(
                        name: field.displayName, value: value, length: field.length(of: value),
                        maximum: field.maximumLength, locale: locale
                    ),
                    rules: WordRules(
                        empty: .retentionTextEmpty,
                        overLimit: .retentionTextOverLimit,
                        edgeSpace: .retentionTextHasEdgeSpace,
                        emptyFix: LocalizedStringResource(
                            "Write it, or take the language out of the message file.", bundle: .here
                        )
                    )
                ) { severity, kind, text, fix in
                    Problem(
                        severity: severity, area: .products, message: text, fix: fix, locale: locale,
                        retentionMessage: name, retentionField: field, path: filePath, kind: kind
                    )
                }
            }
        }
        return problems
    }

    private func validateRetentionImages(_ images: [URL], of message: RetentionMessage) -> [Problem] {
        let name = message.referenceName
        guard images.count < 2 else {
            let files = images.map(\.lastPathComponent).formatted(.list(type: .and, width: .narrow))
            return [Problem(
                severity: .error,
                area: .products,
                message: LocalizedStringResource(
                    "The retention message \(name) has more than one image: \(files).", bundle: .here
                ),
                fix: LocalizedStringResource("Keep one. A message shows one image in every language.", bundle: .here),
                retentionMessage: name,
                path: retentionPath(for: name),
                kind: .retentionTwoImages
            )]
        }
        guard let url = images.first else { return [] }

        let path = "\(config.productsPath)/\(ProductStore.retentionFolderName)/\(url.lastPathComponent)"
        let file = ImageInspector.inspect(url: url)
        guard let width = file.pixelWidth, let height = file.pixelHeight else {
            return [Problem(
                severity: .error,
                area: .products,
                message: LocalizedStringResource("\(url.lastPathComponent) could not be read as an image.", bundle: .here),
                fix: LocalizedStringResource("Save it again as a PNG or a JPEG.", bundle: .here),
                retentionMessage: name,
                path: path,
                kind: .retentionImageUnreadable
            )]
        }
        guard RetentionMessage.imageSizes.contains(where: { $0.width == width && $0.height == height }) else {
            return [Problem(
                severity: .error,
                area: .products,
                message: LocalizedStringResource(
                    "\(url.lastPathComponent) is \(width) x \(height) pixels.", bundle: .here
                ),
                fix: LocalizedStringResource(
                    "Make it 3840 x 2160 or 5244 x 2950 pixels. App Store Connect takes no other size.",
                    bundle: .here
                ),
                retentionMessage: name,
                path: path,
                kind: .retentionImageWrongSize
            )]
        }
        return []
    }

    func retentionPath(for name: String) -> String {
        "\(config.productsPath)/\(ProductStore.retentionFolderName)/\(name).json"
    }
}
