import Foundation

/// Everything the images can be wrong about.
extension Validator {
    func validateScreenshots(_ content: VersionContent) -> [Problem] {
        var problems: [Problem] = []
        let deviceClasses = config.resolvedDeviceClasses
        guard deviceClasses.isEmpty == false else { return problems }

        for deviceClass in deviceClasses {
            problems += validateDeviceClass(deviceClass, content: content)
        }
        return problems
    }

    private func validateDeviceClass(_ deviceClass: DeviceClass, content: VersionContent) -> [Problem] {
        var problems: [Problem] = []
        var imageNamesByLocale: [String: Set<String>] = [:]

        let sourceFiles = content.screenshots(
            locale: config.sourceLocale, deviceClassID: deviceClass.id
        )

        for locale in config.writtenLocales.sorted() {
            let files = content.screenshots(locale: locale, deviceClassID: deviceClass.id)
            let folder = "\(screenshotsPath(content))/\(locale)/\(deviceClass.id)"
            imageNamesByLocale[locale] = Set(files.map { ScreenshotNaming.imageName(of: $0.fileName) })

            // App Store Connect shows the source language's screenshots for a
            // language that has none. The tick is that decision, so it says
            // nothing. It wins over files in the folder, and the page and the
            // push plan say those are not used.
            if config.usesSourceScreenshots(locale: locale, deviceClassID: deviceClass.id) {
                continue
            }

            if files.isEmpty {
                problems.append(emptySet(locale: locale, deviceClass: deviceClass, folder: folder))
                continue
            }

            problems += validateScreenshotSet(files, deviceClass: deviceClass, locale: locale, folder: folder)

            problems += validateCopiesOfSource(
                files,
                sourceFiles: sourceFiles,
                deviceClass: deviceClass,
                locale: locale,
                folder: folder
            )
        }

        problems += validateImageNamesMatchAcrossLocales(
            imageNamesByLocale, deviceClass: deviceClass, content: content
        )
        return problems
    }

    /// A device class with nothing in its folder.
    ///
    /// App Store Connect shows the source language's screenshots wherever a
    /// language has none of its own. For a language that reads the same words,
    /// such as `en-GB` beside `en-US`, that is a decision somebody makes with
    /// the checkbox, so an empty folder without it is a half-finished export
    /// and an error.
    ///
    /// For a language that reads different words it is no decision at all. It
    /// is a listing in one language showing pictures in another, and App Store
    /// Connect accepts it. So it warns rather than blocking the push, and
    /// somebody who means it can silence it.
    private func emptySet(locale: String, deviceClass: DeviceClass, folder: String) -> Problem {
        guard locale != config.sourceLocale else {
            return Problem(
                severity: .error,
                area: .screenshots,
                message: LocalizedStringResource("\(locale) has no \(deviceClass.displayName) screenshots.", bundle: .here),
                fix: LocalizedStringResource("""
                App Store Connect needs at least one. Put them in \(folder). \
                Every other language falls back to this one.
                """, bundle: .here),
                locale: locale,
                deviceClassID: deviceClass.id,
                path: folder,
                kind: .screenshotsMissing
            )
        }

        guard config.sharesSourceLanguage(locale) == false else {
            return Problem(
                severity: .error,
                area: .screenshots,
                message: LocalizedStringResource("\(locale) has no \(deviceClass.displayName) screenshots.", bundle: .here),
                fix: LocalizedStringResource("""
                App Store Connect needs at least one. Put them in \(folder), or say \
                this language shows the \(config.sourceLocale) ones.
                """, bundle: .here),
                locale: locale,
                deviceClassID: deviceClass.id,
                path: folder,
                kind: .screenshotsMissing
            )
        }

        return Problem(
            severity: .warning,
            area: .screenshots,
            message: LocalizedStringResource(
                "The \(deviceClass.displayName) screenshots are not translated into \(locale).",
                bundle: .here
            ),
            fix: LocalizedStringResource("""
            App Store Connect shows the \(config.sourceLocale) ones instead. \
            Put \(locale) screenshots in \(folder).
            """, bundle: .here),
            locale: locale,
            deviceClassID: deviceClass.id,
            path: folder,
            kind: .screenshotsNotTranslated
        )
    }

    /// Screenshots that are the source language's files, byte for byte.
    ///
    /// A folder somebody filled with the English pictures reads as a full set
    /// to every other rule here. The bytes are the only thing that says nobody
    /// translated it.
    ///
    /// Asked only of a language that reads different words. `en-GB` showing the
    /// `en-US` pictures is the right answer, and it has a checkbox for saying
    /// so.
    ///
    /// The count is in the fix rather than in the message. A message that
    /// counts would change from "2 of 5" to "1 of 5" the moment somebody
    /// translates one picture, and that would throw away the silence they put
    /// on it.
    private func validateCopiesOfSource(
        _ files: [ScreenshotFile],
        sourceFiles: [ScreenshotFile],
        deviceClass: DeviceClass,
        locale: String,
        folder: String
    ) -> [Problem] {
        guard
            locale != config.sourceLocale,
            config.sharesSourceLanguage(locale) == false,
            sourceFiles.isEmpty == false
        else {
            return []
        }

        // A set can hold two files showing one thing, so the first one wins
        // rather than the dictionary trapping on a repeated key.
        let sourceByImageName = Dictionary(
            sourceFiles.map { (ScreenshotNaming.imageName(of: $0.fileName), $0) },
            uniquingKeysWith: { first, _ in first }
        )

        // One source language file can be the twin of more than one file here,
        // so its fingerprint is kept rather than read again.
        var digests: [URL: String] = [:]
        var copies = 0

        for file in files {
            guard let twin = sourceByImageName[ScreenshotNaming.imageName(of: file.fileName)] else { continue }
            // Size first, because it is already in memory. Two files of a
            // different size cannot be one file, and reading a hundred images
            // to learn that would make every check slow.
            guard
                file.byteCount == twin.byteCount,
                file.pixelWidth != nil,
                file.pixelWidth == twin.pixelWidth,
                file.pixelHeight == twin.pixelHeight,
                let mine = digest(of: file.url, into: &digests),
                let theirs = digest(of: twin.url, into: &digests),
                mine == theirs
            else {
                continue
            }
            copies += 1
        }

        guard copies > 0 else { return [] }

        return [Problem(
            severity: .warning,
            area: .screenshots,
            message: LocalizedStringResource("""
            The \(deviceClass.displayName) screenshots in \(locale) are the \
            \(config.sourceLocale) files.
            """, bundle: .here),
            fix: LocalizedStringResource("""
            \(copies) of \(files.count) are the same file, byte for byte. \
            Put \(locale) screenshots in \(folder).
            """, bundle: .here),
            locale: locale,
            deviceClassID: deviceClass.id,
            path: folder,
            kind: .screenshotsCopiedFromSource
        )]
    }

    /// A file that cannot be read has no fingerprint, and `validateFile`
    /// already reports it. Answering nil here leaves that one report alone.
    private func digest(of url: URL, into digests: inout [URL: String]) -> String? {
        if let known = digests[url] { return known }
        guard let made = try? FileChecksum.md5(of: url) else { return nil }
        digests[url] = made
        return made
    }

    /// What every set is checked for, in a version, a treatment or a custom
    /// product page: the count, each file, and the names.
    func validateScreenshotSet(
        _ files: [ScreenshotFile],
        deviceClass: DeviceClass,
        locale: String,
        folder: String
    ) -> [Problem] {
        var problems: [Problem] = []
        if files.count > DeviceClass.maximumScreenshotsPerSet {
            problems.append(Problem(
                severity: .error,
                area: .screenshots,
                message: LocalizedStringResource("""
                \(locale) has \(files.count) \(deviceClass.displayName) screenshots, \
                and the limit is \(DeviceClass.maximumScreenshotsPerSet).
                """, bundle: .here),
                locale: locale,
                deviceClassID: deviceClass.id,
                path: folder,
                kind: .screenshotsOverLimit
            ))
        }
        for file in files {
            problems += validateFile(file, deviceClass: deviceClass, locale: locale, folder: folder)
        }
        problems += validateNames(files, deviceClass: deviceClass, locale: locale, folder: folder)
        return problems
    }

    /// The sets of a treatment or a custom product page. Only what App Store
    /// Connect refuses, and the names. Whether the place still exists is a
    /// question for App Store Connect, and the plan answers it.
    func validateScreenshotSets(_ sets: [PlacedFiles<ScreenshotFile>]) -> [Problem] {
        var problems: [Problem] = []
        let deviceClasses = Dictionary(uniqueKeysWithValues: config.resolvedDeviceClasses.map { ($0.id, $0) })

        for set in sets where set.files.isEmpty == false {
            let (slot, files) = (set.slot, set.files)
            let folder = set.place.screenshotsPath(config: config, locale: slot.locale, deviceClassID: slot.deviceClassID)
            guard let deviceClass = deviceClasses[slot.deviceClassID] else {
                problems.append(Problem(
                    severity: .warning,
                    area: .screenshots,
                    message: LocalizedStringResource("""
                    \(folder) holds \(files.count) images for a device class this project \
                    does not list.
                    """, bundle: .here),
                    fix: LocalizedStringResource(
                        "Nothing uploads them. List the device class in asckit.json, or remove the folder.",
                        bundle: .here
                    ),
                    locale: slot.locale,
                    deviceClassID: slot.deviceClassID,
                    path: folder,
                    kind: .deviceClassNotKnown
                ))
                continue
            }
            problems += validateScreenshotSet(files, deviceClass: deviceClass, locale: slot.locale, folder: folder)
        }
        return problems
    }

    /// Files whose names do not follow the rule.
    ///
    /// The name goes to App Store Connect with the image, and the next push
    /// looks for it there. A set uploaded under a name ASCKit would not write
    /// is a set the next push reads as somebody else's work.
    private func validateNames(
        _ files: [ScreenshotFile],
        deviceClass: DeviceClass,
        locale: String,
        folder: String
    ) -> [Problem] {
        let wrong = files.enumerated().filter { position, file in
            file.fileName != ScreenshotNaming.fileName(
                position: position + 1,
                imageName: ScreenshotNaming.imageName(of: file.fileName),
                deviceClass: deviceClass,
                locale: locale,
                extension: file.url.pathExtension
            )
        }
        guard wrong.isEmpty == false else { return [] }

        // The list is inside the sentence rather than added to it, so the whole
        // sentence is one catalog entry.
        let names = wrong.map(\.element.fileName).joined(separator: ", ")

        return [Problem(
            severity: .warning,
            area: .screenshots,
            message: LocalizedStringResource("""
            \(wrong.count) of the \(locale) \(deviceClass.displayName) screenshots are \
            not named the way ASCKit names them: \(names).
            """, bundle: .here),
            fix: LocalizedStringResource("""
            The name goes to App Store Connect with the image, and the next push looks for \
            it there. Run asckit fix-names, or add or remove one image in this set, which \
            names the whole set again.
            """, bundle: .here),
            locale: locale,
            deviceClassID: deviceClass.id,
            path: folder,
            kind: .screenshotsNamedWrong
        )]
    }

    func validateFile(
        _ file: ScreenshotFile,
        deviceClass: DeviceClass,
        locale: String,
        folder: String
    ) -> [Problem] {
        var problems: [Problem] = []
        let path = "\(folder)/\(file.fileName)"

        guard let width = file.pixelWidth, let height = file.pixelHeight else {
            problems.append(Problem(
                severity: .error,
                area: .screenshots,
                message: LocalizedStringResource("\(file.fileName) could not be read as an image.", bundle: .here),
                fix: LocalizedStringResource("Everything in this folder is uploaded. Remove the file or replace it.", bundle: .here),
                locale: locale,
                deviceClassID: deviceClass.id,
                path: path,
                kind: .screenshotUnreadable
            ))
            return problems
        }

        let rules = ImageRules.screenshot(of: deviceClass, refData: refData)
        if rules.accepts(width: width, height: height) == false {
            problems.append(Problem(
                severity: .error,
                area: .screenshots,
                message: LocalizedStringResource("""
                \(file.fileName) is \(file.pixelDescription), \
                which \(deviceClass.displayName) does not accept.
                """, bundle: .here),
                fix: LocalizedStringResource(
                    "Accepted sizes are \(rules.sizeList), or the same pair swapped for landscape.",
                    bundle: .here
                ),
                locale: locale,
                deviceClassID: deviceClass.id,
                path: path,
                kind: .screenshotWrongSize
            ))
        }

        problems += validateFileFacts(file, rules: rules, deviceClass: deviceClass, locale: locale, path: path)

        if file.hasAlpha == true, rules.alphaAllowed == false {
            problems.append(Problem(
                severity: .error,
                area: .screenshots,
                message: LocalizedStringResource("\(file.fileName) has an alpha channel.", bundle: .here),
                fix: LocalizedStringResource("""
                App Store Connect refuses it. Export it again without one. Artwork that \
                looks fully opaque still gets an alpha channel from most design tools.
                """, bundle: .here),
                locale: locale,
                deviceClassID: deviceClass.id,
                path: path,
                kind: .screenshotHasAlpha
            ))
        }

        if file.fileName.first?.isNumber == false {
            problems.append(Problem(
                severity: .warning,
                area: .screenshots,
                message: LocalizedStringResource("\(file.fileName) does not start with a number.", bundle: .here),
                fix: LocalizedStringResource("The file name sets the order Apple shows, so name them 01, 02 and so on.", bundle: .here),
                locale: locale,
                deviceClassID: deviceClass.id,
                path: path,
                kind: .screenshotHasNoNumber
            ))
        }

        return problems
    }

    /// A slot that exists in one language and not another is almost always a
    /// half-finished export rather than a decision.
    private func validateImageNamesMatchAcrossLocales(
        _ imageNamesByLocale: [String: Set<String>],
        deviceClass: DeviceClass,
        content: VersionContent
    ) -> [Problem] {
        guard let reference = imageNamesByLocale[config.sourceLocale], reference.isEmpty == false else {
            return []
        }

        var problems: [Problem] = []
        for locale in config.writtenLocales.sorted() where locale != config.sourceLocale {
            guard let names = imageNamesByLocale[locale], names.isEmpty == false else { continue }

            let missing = reference.subtracting(names).sorted()
            if missing.isEmpty == false {
                problems.append(Problem(
                    severity: .warning,
                    area: .screenshots,
                    message: LocalizedStringResource("""
                    \(locale) is missing \(deviceClass.displayName) \
                    \(missing.joined(separator: ", ")), which \(config.sourceLocale) has.
                    """, bundle: .here),
                    locale: locale,
                    deviceClassID: deviceClass.id,
                    path: "\(screenshotsPath(content))/\(locale)/\(deviceClass.id)",
                    kind: .screenshotsMissingSiblings
                ))
            }
        }
        return problems
    }
}

// MARK: - File size and type

extension Validator {
    /// What App Store Connect says about the file itself, apart from its
    /// pixels. Only the reference data names these, so without it nothing is
    /// checked here.
    func validateFileFacts(
        _ file: ScreenshotFile,
        rules: ImageRules,
        deviceClass: DeviceClass,
        locale: String,
        path: String
    ) -> [Problem] {
        var problems: [Problem] = []
        if let limit = rules.maxFileSize, file.byteCount > limit {
            let size = Int64(file.byteCount).formatted(.byteCount(style: .file))
            let most = Int64(limit).formatted(.byteCount(style: .file))
            problems.append(Problem(
                severity: .error,
                area: .screenshots,
                message: LocalizedStringResource("\(file.fileName) is \(size).", bundle: .here),
                fix: LocalizedStringResource("App Store Connect takes a file of at most \(most). Export it smaller.", bundle: .here),
                locale: locale,
                deviceClassID: deviceClass.id,
                path: path,
                kind: .screenshotTooLarge
            ))
        }
        if rules.accepts(fileName: file.fileName) == false {
            let kinds = rules.fileExtensions.formatted(.list(type: .or, width: .narrow))
            problems.append(Problem(
                severity: .error,
                area: .screenshots,
                message: LocalizedStringResource("App Store Connect does not take \(file.fileName) as a screenshot.", bundle: .here),
                fix: LocalizedStringResource("Export it as \(kinds).", bundle: .here),
                locale: locale,
                deviceClassID: deviceClass.id,
                path: path,
                kind: .screenshotWrongFileType
            ))
        }
        return problems
    }
}
