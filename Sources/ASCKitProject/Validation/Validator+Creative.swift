import ASCKitAPI
import Foundation

// MARK: - The checks

extension Validator {
    func validateCreative(_ content: VersionContent) -> [Problem] {
        // The tick wins over files in the folder and is a decision, so it says
        // nothing. The page and the push plan say the files are not used.
        validateCreativeFolder(content.creativeFolder, root: creativePath(content))
    }

    /// The languages that show the source language's art. A name that the
    /// push cannot use reads as silence, so it is reported.
    func validateSourceCreative() -> [Problem] {
        var problems: [Problem] = []
        for locale in Set(config.usesSourceCreative).sorted() {
            if locale == config.sourceLocale || config.locales.contains(locale) == false {
                problems.append(Problem(
                    severity: .error,
                    area: .configuration,
                    message: LocalizedStringResource("""
                    usesSourceCreative names \(locale), which is the source language \
                    or a language this project does not ship.
                    """, bundle: .here),
                    fix: LocalizedStringResource("Take it out of usesSourceCreative.", bundle: .here),
                    locale: locale,
                    path: Project.defaultConfigName,
                    kind: .sourceCreativeLocaleNotUsable
                ))
            } else if config.sharesSourceLanguage(locale) == false {
                problems.append(Problem(
                    severity: .warning,
                    area: .configuration,
                    message: LocalizedStringResource("""
                    usesSourceCreative names \(locale), which reads different words \
                    from \(config.sourceLocale).
                    """, bundle: .here),
                    fix: LocalizedStringResource(
                        "\(locale) needs a header of its own. Take it out of usesSourceCreative.", bundle: .here
                    ),
                    locale: locale,
                    path: Project.defaultConfigName,
                    kind: .sourceCreativeLocaleReadsDifferently
                ))
            }
        }
        return problems
    }

    func validateExperimentCreative(_ experiments: ExperimentContent) -> [Problem] {
        experiments.creative.keys.sorted().flatMap { treatment in
            validateCreativeFolder(
                experiments.creative[treatment] ?? CreativeFolder(),
                root: "\(ExperimentFolders.folderName)/\(treatment)/\(CreativeFolder.folderName)"
            )
        }
    }

    func validateCreativeFolder(_ folder: CreativeFolder, root: String) -> [Problem] {
        var problems: [Problem] = []

        for locale in Set(folder.files.keys).union(folder.strays.keys).sorted() {
            let path = "\(root)/\(locale)"
            for stray in folder.strays[locale] ?? [] {
                problems.append(creativeProblem(.warning, .creativeFileNotKnown, locale: locale, path: "\(path)/\(stray)",
                                                LocalizedStringResource("ASCKit does not know what \(stray) is for.", bundle: .here),
                                                LocalizedStringResource("""
                                                Name it header or search-results, with its extension. Nothing uploads it.
                                                """, bundle: .here)))
            }
            for role in CreativeRole.allCases {
                let files = folder.files[locale]?[role] ?? []
                if files.count > 1 {
                    let names = files.map(\.fileName).formatted(.list(type: .and, width: .narrow))
                    problems.append(creativeProblem(.error, .creativeTwoFiles, locale: locale, path: path,
                                                    LocalizedStringResource("\(path) has \(names).", bundle: .here),
                                                    LocalizedStringResource("Keep one. App Store Connect shows one.",
                                                                            bundle: .here)))
                }
                guard let file = files.first else { continue }
                problems += validateCreativeFile(file, role: role, locale: locale, path: "\(path)/\(file.fileName)")
            }

            let header = folder.file(locale: locale, role: .header)
            let search = folder.file(locale: locale, role: .searchResults)
            // With no search results file, App Store Connect shows the header there.
            if let header, search == nil {
                let fitsSearch = CreativeRules.rules(for: .searchResults, refData: refData).matching(header).isEmpty == false
                let universal = CreativeRules.rules(for: .header, refData: refData).matching(header).contains(where: \.universal)
                if fitsSearch == false || universal == false {
                    problems.append(creativeProblem(.error, .creativeHeaderNotUniversal, locale: locale,
                                                    path: "\(path)/\(header.fileName)",
                                                    LocalizedStringResource("""
                                                    \(header.fileName) also goes into search results, \
                                                    because this language has no search results file. Only a \
                                                    universal image fits both.
                                                    """, bundle: .here),
                                                    LocalizedStringResource("""
                                                    Use a 5244x2950 png, or add a search-results file for this language.
                                                    """, bundle: .here)))
                }
            }
        }
        return problems
    }

    func validateCreativeFile(_ file: CreativeFile, role: CreativeRole, locale: String, path: String) -> [Problem] {
        var problems: [Problem] = []
        let ext = file.url.pathExtension.lowercased()
        guard MediaExtensions.image.contains(ext) || MediaExtensions.video.contains(ext) else {
            return [creativeProblem(.error, .creativeWrongFileType, locale: locale, path: path,
                                    LocalizedStringResource("App Store Connect does not take \(file.fileName).",
                                                            bundle: .here),
                                    LocalizedStringResource("Export it as png, jpg, mov, mp4 or m4v.", bundle: .here))]
        }
        guard let width = file.pixelWidth, let height = file.pixelHeight else {
            return [creativeProblem(.error, .creativeUnreadable, locale: locale, path: path,
                                    LocalizedStringResource("\(file.fileName) could not be read.", bundle: .here), nil)]
        }

        let rules = CreativeRules.rules(for: role, refData: refData)
        let matches = rules.matching(file)
        if matches.isEmpty {
            problems.append(creativeProblem(.error, .creativeWrongSize, locale: locale, path: path,
                                            LocalizedStringResource("\(file.fileName) is \("\(width)x\(height)") pixels.",
                                                                    bundle: .here),
                                            LocalizedStringResource("""
                                            Here App Store Connect takes \(rules.sizeList), in the file types each \
                                            size allows.
                                            """, bundle: .here)))
        }
        if file.media == .image, file.hasAlpha == true, matches.allSatisfy({ $0.alphaAllowed == false }) {
            problems.append(creativeProblem(.error, .creativeHasAlpha, locale: locale, path: path,
                                            LocalizedStringResource("\(file.fileName) has an alpha channel.",
                                                                    bundle: .here),
                                            LocalizedStringResource("Export it again without one.", bundle: .here)))
        }
        if file.media == .video {
            if let duration = file.duration, rules.duration.contains(duration) == false {
                let length = Duration.seconds(duration).formatted(.units(allowed: [.seconds], fractionalPart: .show(length: 1)))
                problems.append(creativeProblem(.error, .creativeWrongLength, locale: locale, path: path,
                                                LocalizedStringResource("\(file.fileName) runs for \(length).",
                                                                        bundle: .here),
                                                LocalizedStringResource("A header or search results video runs 5 to 30 seconds.",
                                                                        bundle: .here)))
            }
            if let rate = file.frameRate, rules.frameRates.contains(rate.rounded()) == false {
                let shown = rate.formatted(.number.precision(.fractionLength(0 ... 2)))
                problems.append(creativeProblem(.error, .creativeWrongFrameRate, locale: locale, path: path,
                                                LocalizedStringResource("\(file.fileName) has \(shown) frames a second.",
                                                                        bundle: .here),
                                                LocalizedStringResource("Export it at 30 or 60 frames a second.",
                                                                        bundle: .here)))
            }
        }
        return problems
    }

    // swiftlint:disable:next function_parameter_count
    private func creativeProblem(
        _ severity: Problem.Severity,
        _ kind: Problem.Kind,
        locale: String,
        path: String,
        _ message: LocalizedStringResource,
        _ fix: LocalizedStringResource?
    ) -> Problem {
        Problem(severity: severity, area: .screenshots, message: message, fix: fix, locale: locale, path: path, kind: kind)
    }
}
