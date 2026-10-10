import ASCKitAPI
import Foundation

/// Checks a project against everything App Store Connect will refuse, plus the
/// things it will accept but you would not want published.
///
/// Nothing here touches the network. That is deliberate: the check has to run
/// in a git hook, and a check that needs credentials is a check nobody runs.
public struct Validator: Sendable {
    let config: ProjectConfig

    /// App Store Connect's own sizes and formats. Nil uses the built-in sizes.
    let refData: AssetLibraryRefData?

    public init(config: ProjectConfig, refData: AssetLibraryRefData? = nil) {
        self.config = config
        self.refData = refData
    }

    /// With the reference data the project keeps in its cache.
    public init(project: Project) {
        self.init(config: project.config, refData: RefDataCache.load(in: project))
    }

    public func validate(_ content: VersionContent) -> [Problem] {
        var problems = validateConfiguration()
        problems += validateIPhoneDuo()
        problems += validateLayout(content)
        problems += validateCopy(content)
        problems += validateScreenshots(content)
        problems += validatePreviews(content)
        problems += validateCreative(content)
        return problems.sortedForDisplay
    }

    /// The in-app purchases, which are not tied to a version and so are checked
    /// on their own rather than as part of one.
    public func validate(_ catalog: ProductCatalog) -> [Problem] {
        var problems = validateProducts(catalog)
        problems += validateSubscriptionGroups(catalog)
        problems += validatePricing(catalog)
        return problems.sortedForDisplay
    }

    /// The images of the Product Page Optimization tests.
    ///
    /// What App Store Connect refuses: a file that is not an image, a size
    /// the device class does not take, an alpha channel, more than ten.
    /// Whether a test still exists is a question for App Store Connect, and
    /// the plan answers it.
    ///
    /// `snapshot` is the last read of the tests. With it, a language of a
    /// treatment that has no screenshots where another language has them
    /// is a warning.
    public func validate(_ experiments: ExperimentContent, snapshot: ExperimentSnapshot? = nil) -> [Problem] {
        var problems = validateScreenshotSets(experiments.screenshots.map { $0.key.placed($0.value) })
        problems += validateTreatmentLanguages(experiments, snapshot: snapshot)
        problems += validateExperimentPreviews(experiments)
        problems += validateExperimentCreative(experiments)
        return problems.sortedForDisplay
    }

    // MARK: - Configuration

    func validateConfiguration() -> [Problem] {
        var problems: [Problem] = []

        for locale in config.locales where StoreLocale.isKnown(locale) == false {
            let suggestion = StoreLocale.suggestion(for: locale)
            problems.append(Problem(
                severity: .error,
                area: .configuration,
                message: LocalizedStringResource("\(locale) is not a locale App Store Connect accepts.", bundle: .here),
                fix: suggestion.map { LocalizedStringResource("Use \($0) instead.", bundle: .here) }
                    ?? LocalizedStringResource(
                        "Check the locale against what asckit pull reports for this app.", bundle: .here
                    ),
                locale: locale,
                path: Project.defaultConfigName,
                kind: .localeNotAccepted
            ))
        }

        for identifier in config.deviceClasses where DeviceClass.named(identifier) == nil {
            problems.append(Problem(
                severity: .error,
                area: .configuration,
                message: LocalizedStringResource("\(identifier) is not a device class ASCKit knows.", bundle: .here),
                fix: LocalizedStringResource("Use one of: \(DeviceClass.all.map(\.id).joined(separator: ", ")).", bundle: .here),
                deviceClassID: identifier,
                path: Project.defaultConfigName,
                kind: .deviceClassNotKnown
            ))
        }

        if config.locales.contains(config.sourceLocale) == false {
            problems.append(Problem(
                severity: .error,
                area: .configuration,
                message: LocalizedStringResource("The source language \(config.sourceLocale) is not in the locale list.", bundle: .here),
                fix: LocalizedStringResource("Add it to locales, or point sourceLocale at one that is there.", bundle: .here),
                locale: config.sourceLocale,
                path: Project.defaultConfigName,
                kind: .sourceLocaleNotListed
            ))
        }

        if config.locales.isEmpty {
            problems.append(Problem(
                severity: .error,
                area: .configuration,
                message: LocalizedStringResource("No languages are listed, so there is nothing to publish.", bundle: .here),
                path: Project.defaultConfigName,
                kind: .noLocalesListed
            ))
        }

        if config.deviceClasses.isEmpty {
            problems.append(Problem(
                severity: .warning,
                area: .configuration,
                message: LocalizedStringResource("No device classes are listed, so no screenshots will be published.", bundle: .here),
                path: Project.defaultConfigName,
                kind: .noDeviceClassesListed
            ))
        }

        let duplicates = Dictionary(grouping: config.locales, by: \.self).filter { $0.value.count > 1 }
        for locale in duplicates.keys.sorted() {
            problems.append(Problem(
                severity: .warning,
                area: .configuration,
                message: LocalizedStringResource("\(locale) is listed more than once.", bundle: .here),
                locale: locale,
                path: Project.defaultConfigName,
                kind: .localeListedTwice
            ))
        }

        problems += validatePlatform()
        problems += validateIgnoredLocales()
        problems += validateSourceScreenshots()
        problems += validateSiblingScreenshots()
        problems += validateSourceCreative()
        return problems
    }

    /// The platform a project names, against the ones ASCKit knows.
    ///
    /// A name nobody recognises reads the same as no name at all, which asks
    /// App Store Connect for every version the app has. So a typo here reads
    /// as silence, and this is what says it.
    private func validatePlatform() -> [Problem] {
        guard let platform = config.platform, Platform.named(platform) == nil else { return [] }

        return [Problem(
            severity: .error,
            area: .configuration,
            message: LocalizedStringResource("\(platform) is not a platform ASCKit knows.", bundle: .here),
            fix: LocalizedStringResource("""
            Use one of: \(Platform.all.map(\.id).joined(separator: ", ")). \
            Leave it out for an app on one platform.
            """, bundle: .here),
            path: Project.defaultConfigName,
            kind: .platformNotKnown
        )]
    }

    /// The languages this project leaves to App Store Connect.
    ///
    /// Ignoring a language turns off every check about it, so a name here that
    /// means nothing is a check somebody thinks they turned off and did not.
    private func validateIgnoredLocales() -> [Problem] {
        var problems: [Problem] = []

        for locale in config.ignoredLocales where config.locales.contains(locale) == false {
            problems.append(Problem(
                severity: .warning,
                area: .configuration,
                message: LocalizedStringResource("""
                ignoredLocales names \(locale), which is not in the locale list.
                """, bundle: .here),
                fix: LocalizedStringResource("""
                Add \(locale) to locales, or take it out of ignoredLocales. \
                A language is ignored by staying in the list and being named here.
                """, bundle: .here),
                locale: locale,
                path: Project.defaultConfigName,
                kind: .ignoredLocaleNotListed
            ))
        }

        if config.isIgnored(config.sourceLocale) {
            problems.append(Problem(
                severity: .error,
                area: .configuration,
                message: LocalizedStringResource("""
                The source language \(config.sourceLocale) is ignored, so nothing would be written.
                """, bundle: .here),
                fix: LocalizedStringResource("""
                Take \(config.sourceLocale) out of ignoredLocales. Every other language \
                is translated from it.
                """, bundle: .here),
                locale: config.sourceLocale,
                path: Project.defaultConfigName,
                kind: .sourceLocaleIgnored
            ))
        }

        return problems
    }

    /// The languages that show the source language's screenshots.
    ///
    /// Every one of these turns an error off, so a name nobody can act on has
    /// to be reported. A typo here reads as silence, and silence reads as a
    /// language that is fine.
    private func validateSourceScreenshots() -> [Problem] {
        var problems: [Problem] = []

        for locale in config.usesSourceScreenshots.keys.sorted() {
            if locale == config.sourceLocale {
                problems.append(Problem(
                    severity: .error,
                    area: .configuration,
                    message: LocalizedStringResource("""
                    \(locale) is the source language, so it cannot show the source \
                    language's screenshots.
                    """, bundle: .here),
                    fix: LocalizedStringResource("""
                    Take it out of usesSourceScreenshots. Every other language falls \
                    back to this one.
                    """, bundle: .here),
                    locale: locale,
                    path: Project.defaultConfigName,
                    kind: .sourceLocaleUsesOwnScreenshots
                ))
                continue
            }

            if config.locales.contains(locale) == false {
                problems.append(Problem(
                    severity: .error,
                    area: .configuration,
                    message: LocalizedStringResource("""
                    usesSourceScreenshots names \(locale), which this project does \
                    not ship.
                    """, bundle: .here),
                    fix: LocalizedStringResource("Add it to locales, or take it out of usesSourceScreenshots.", bundle: .here),
                    locale: locale,
                    path: Project.defaultConfigName,
                    kind: .sourceScreenshotsLocaleNotShipped
                ))
                continue
            }

            if config.sharesSourceLanguage(locale) == false {
                problems.append(Problem(
                    severity: .warning,
                    area: .configuration,
                    message: LocalizedStringResource("""
                    usesSourceScreenshots names \(locale), which reads different \
                    words from \(config.sourceLocale).
                    """, bundle: .here),
                    fix: LocalizedStringResource("""
                    \(locale) needs screenshots of its own. Take it out of \
                    usesSourceScreenshots.
                    """, bundle: .here),
                    locale: locale,
                    path: Project.defaultConfigName,
                    kind: .sourceScreenshotsLocaleReadsDifferently
                ))
            }

            for identifier in config.usesSourceScreenshots[locale, default: []].sorted()
                where config.deviceClasses.contains(identifier) == false {
                problems.append(Problem(
                    severity: .error,
                    area: .configuration,
                    message: LocalizedStringResource("""
                    usesSourceScreenshots says \(locale) shows the source language's \
                    \(identifier) screenshots, and this project does not list \(identifier).
                    """, bundle: .here),
                    fix: LocalizedStringResource("Use one of: \(config.deviceClasses.joined(separator: ", ")).", bundle: .here),
                    locale: locale,
                    deviceClassID: identifier,
                    path: Project.defaultConfigName,
                    kind: .sourceScreenshotsDeviceClassNotListed
                ))
            }
        }
        return problems
    }

    /// The languages that take the screenshots of the language beside them.
    ///
    /// A new version folder makes each of these copies, and leaves out one it
    /// cannot make. A typo here reads as a set that stays old, so it is
    /// reported. `SiblingScreenshots` holds the rule, so the check and the copy
    /// refuse the same entries.
    private func validateSiblingScreenshots() -> [Problem] {
        var problems: [Problem] = []

        for locale in config.copiesScreenshotsFrom.keys.sorted() {
            let copies = config.copiesScreenshotsFrom[locale, default: [:]].sorted { $0.key < $1.key }

            for (identifier, donor) in copies
                where SiblingScreenshots.donor(of: locale, deviceClassID: identifier, config: config) == nil {
                problems.append(Problem(
                    severity: .warning,
                    area: .configuration,
                    message: LocalizedStringResource("""
                    copiesScreenshotsFrom says \(locale) takes the \(identifier) screenshots \
                    of \(donor), and that copy cannot be made.
                    """, bundle: .here),
                    fix: LocalizedStringResource("""
                    Both have to be languages this project ships, and the same language, such \
                    as es-ES and es-MX. \(identifier) has to be a device class it lists. \
                    Correct the entry, or take it out of copiesScreenshotsFrom.
                    """, bundle: .here),
                    locale: locale,
                    deviceClassID: identifier,
                    path: Project.defaultConfigName,
                    kind: .screenshotCopyCannotBeMade
                ))
            }
        }
        return problems
    }

    // MARK: - Layout

    func validateLayout(_ content: VersionContent) -> [Problem] {
        validateInformationFiles(content) + validateScreenshotFolders(content)
    }

    /// The app information files: the ones that cannot be read, the ones that
    /// are not there, and the ones that are there for a language nobody ships.
    private func validateInformationFiles(_ content: VersionContent) -> [Problem] {
        var problems: [Problem] = []
        let expected = Set(config.locales)

        for (locale, reason) in content.unreadableInformation {
            problems.append(Problem(
                severity: .error,
                area: .layout,
                message: LocalizedStringResource("\(locale).json could not be read.", bundle: .here),
                // The reason comes from the decoder, in its own words.
                fix: LocalizedStringResource("\(reason)", bundle: .here),
                locale: locale,
                path: informationPath(content, locale),
                kind: .appInformationUnreadable
            ))
        }

        for locale in config.writtenLocales.sorted()
            where content.appInformation[locale] == nil && content.unreadableInformation[locale] == nil {
            problems.append(Problem(
                severity: .warning,
                area: .layout,
                message: LocalizedStringResource("\(locale) is listed but has no app information file.", bundle: .here),
                fix: LocalizedStringResource(
                    "Write \(informationPath(content, locale)), or take \(locale) out of the locale list.",
                    bundle: .here
                ),
                locale: locale,
                path: informationPath(content, locale),
                kind: .appInformationFileMissing
            ))
        }

        for locale in content.appInformation.keys.sorted() where expected.contains(locale) == false {
            problems.append(Problem(
                severity: .warning,
                area: .layout,
                message: LocalizedStringResource("\(locale).json is there but \(locale) is not in the locale list.", bundle: .here),
                fix: LocalizedStringResource("Add \(locale) to the list, or delete the file. It will not be published.", bundle: .here),
                locale: locale,
                path: informationPath(content, locale),
                kind: .appInformationFileNotListed
            ))
        }

        for (locale, copy) in content.appInformation where copy.locale.isEmpty == false && copy.locale != locale {
            problems.append(Problem(
                severity: .error,
                area: .layout,
                message: LocalizedStringResource("\(locale).json says its locale is \(copy.locale).", bundle: .here),
                fix: LocalizedStringResource(
                    "The file name decides. Make the locale field say \(locale), or rename the file.",
                    bundle: .here
                ),
                locale: locale,
                path: informationPath(content, locale),
                kind: .appInformationLocaleMismatch
            ))
        }

        return problems
    }

    /// The screenshot folders that name a language or a device class the project
    /// does not list.
    private func validateScreenshotFolders(_ content: VersionContent) -> [Problem] {
        var problems: [Problem] = []
        let expected = Set(config.locales)

        for locale in content.screenshotLocales.sorted() where expected.contains(locale) == false {
            problems.append(Problem(
                severity: .warning,
                area: .layout,
                message: LocalizedStringResource("There are screenshots for \(locale), which is not in the locale list.", bundle: .here),
                fix: LocalizedStringResource("Add \(locale) to the list, or delete the folder. It will not be published.", bundle: .here),
                locale: locale,
                path: "\(screenshotsPath(content))/\(locale)",
                kind: .screenshotFolderLocaleNotListed
            ))
        }

        let knownDeviceClasses = Set(config.deviceClasses)
        let foundDeviceClasses = Set(content.screenshots.keys.map(\.deviceClassID))
        for identifier in foundDeviceClasses.subtracting(knownDeviceClasses).sorted() {
            problems.append(Problem(
                severity: .warning,
                area: .layout,
                message: LocalizedStringResource(
                    "There are screenshots in a \(identifier) folder, which the project does not list.",
                    bundle: .here
                ),
                fix: LocalizedStringResource(
                    "Add \(identifier) to deviceClasses, or delete the folder. It will not be published.",
                    bundle: .here
                ),
                deviceClassID: identifier,
                kind: .screenshotFolderDeviceClassNotListed
            ))
        }

        return problems
    }
}
