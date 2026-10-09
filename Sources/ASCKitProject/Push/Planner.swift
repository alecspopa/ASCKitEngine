import ASCKitAPI
import Foundation

/// Works out what a push would do, by comparing what is on disk against what
/// App Store Connect holds.
public enum Planner {
    /// Screenshots, previews and art compare against the App Asset Library,
    /// through the record of what this project uploaded.
    public static func plan(
        local: VersionContent,
        config: ProjectConfig,
        remote: RemoteListing,
        record: AssetRecord = AssetRecord()
    ) -> ChangePlan {
        var textChanges: [ChangePlan.TextChange] = []
        var skipped: [ChangePlan.Skipped] = []
        var missingLocales: [String] = []

        for locale in config.writtenLocales.sorted() {
            guard let copy = local.appInformation[locale] else {
                skipped.append(.init(
                    locale: locale,
                    reason: LocalizedStringResource("no app information file", bundle: .here)
                ))
                continue
            }

            guard copy.status.canPublish else {
                skipped.append(.init(
                    locale: locale,
                    reason: LocalizedStringResource("marked \(copy.status.rawValue)", bundle: .here)
                ))
                continue
            }

            // ASCKit never makes a language on App Store Connect. A page has
            // to be there before anything can be written into it.
            guard remote.locales.contains(locale) else {
                missingLocales.append(locale)
                continue
            }

            if remote.appInfoLocalizations[locale] == nil {
                skipped.append(.init(
                    locale: locale,
                    reason: LocalizedStringResource("App Information has no \(locale)", bundle: .here)
                ))
            }
            if remote.versionLocalizations[locale] == nil {
                skipped.append(.init(
                    locale: locale,
                    reason: LocalizedStringResource("this version has no \(locale)", bundle: .here)
                ))
            }

            textChanges += changes(for: copy, locale: locale, remote: remote)
        }

        let screenshotPlans = plans(for: local, config: config, remote: remote, record: record)
        let previewPlans = previewPlans(for: local, config: config, remote: remote, record: record)
        let creativePlans = CreativePlanner.plans(
            folder: usedCreative(local.creativeFolder, config: config),
            locales: config.writtenLocales.filter {
                local.appInformation[$0]?.status.canPublish == true && remote.versionLocalizations[$0] != nil
            },
            placements: remote.placements,
            record: record
        )

        return ChangePlan(
            versionString: remote.versionString,
            versionState: remote.versionState,
            textChanges: textChanges,
            missingLocales: missingLocales,
            screenshotPlans: screenshotPlans,
            previewPlans: previewPlans,
            creativePlans: creativePlans,
            unusedFiles: unusedFiles(in: local, config: config),
            blocked: blocked(
                textChanges: textChanges,
                screenshotPlans: screenshotPlans,
                changingPreviews: previewPlans.count(where: \.changesAnything)
                    + creativePlans.count(where: \.changesAnything),
                remote: remote
            ),
            skipped: skipped
        )
    }

    // MARK: - Text

    private static func changes(
        for copy: AppInformation,
        locale: String,
        remote: RemoteListing
    ) -> [ChangePlan.TextChange] {
        var changes: [ChangePlan.TextChange] = []

        for field in copy.fields.presentFields {
            guard let newValue = copy.fields[field] else { continue }

            // Nothing goes into a resource App Store Connect has not made. The
            // name lives on the app information and the description on the
            // version, and a language can have one and not the other.
            guard holds(field, locale: locale, remote: remote) else { continue }
            let oldValue = remoteValue(field, locale: locale, remote: remote)

            // Apple returns an empty string for a field that was never set, so
            // an empty old value is an add rather than a change to nothing.
            if let oldValue, oldValue.isEmpty == false {
                if oldValue != newValue {
                    changes.append(.init(
                        locale: locale, field: field, action: .change,
                        oldValue: oldValue, newValue: newValue
                    ))
                }
            } else {
                changes.append(.init(
                    locale: locale, field: field, action: .add,
                    oldValue: nil, newValue: newValue
                ))
            }
        }
        return changes
    }

    /// Whether App Store Connect already holds the resource this field lives
    /// on, for this language.
    private static func holds(
        _ field: MetadataField,
        locale: String,
        remote: RemoteListing
    ) -> Bool {
        field.isAppInfoField
            ? remote.appInfoLocalizations[locale] != nil
            : remote.versionLocalizations[locale] != nil
    }

    private static func remoteValue(
        _ field: MetadataField,
        locale: String,
        remote: RemoteListing
    ) -> String? {
        let source = field.isAppInfoField
            ? remote.appInfoLocalizations[locale]
            : remote.versionLocalizations[locale]
        return source?.values[field.rawValue]
    }

    // MARK: - Screenshots

    private static func plans(
        for local: VersionContent,
        config: ProjectConfig,
        remote: RemoteListing,
        record: AssetRecord
    ) -> [ChangePlan.ScreenshotPlan] {
        var plans: [ChangePlan.ScreenshotPlan] = []

        for locale in config.writtenLocales.sorted() {
            // A language that will not be published gets no screenshots
            // either, and neither does one this version has no page for.
            guard local.appInformation[locale]?.status.canPublish == true else { continue }
            guard remote.versionLocalizations[locale] != nil else { continue }

            for deviceClass in config.resolvedDeviceClasses {
                // The tick wins over files in the folder. App Store Connect
                // shows the source language's on a language with none.
                let files = config.usesSourceScreenshots(locale: locale, deviceClassID: deviceClass.id)
                    ? []
                    : local.screenshots(locale: locale, deviceClassID: deviceClass.id)
                let type = deviceClass.screenshotPlacementType
                let current = LibraryPlanner.current(
                    in: remote.placements, locale: locale, group: deviceClass.placementGroup, type: type
                )
                guard files.isEmpty == false || current.isEmpty == false else { continue }

                plans.append(ChangePlan.ScreenshotPlan(
                    locale: locale,
                    deviceClass: deviceClass,
                    localFiles: files,
                    library: LibraryPlanner.slot(
                        files: files.map(\.libraryFile), current: current, record: record,
                        group: deviceClass.placementGroup, type: type
                    )
                ))
            }
        }
        return plans
    }

    /// The previews of each language and device class that takes them.
    private static func previewPlans(
        for local: VersionContent,
        config: ProjectConfig,
        remote: RemoteListing,
        record: AssetRecord
    ) -> [ChangePlan.PreviewPlan] {
        var plans: [ChangePlan.PreviewPlan] = []
        for locale in config.writtenLocales.sorted() {
            guard local.appInformation[locale]?.status.canPublish == true else { continue }
            guard remote.versionLocalizations[locale] != nil else { continue }

            for deviceClass in config.resolvedDeviceClasses where deviceClass.takesPreviews {
                let files = local.previews(locale: locale, deviceClassID: deviceClass.id)
                let current = LibraryPlanner.current(
                    in: remote.placements, locale: locale, group: deviceClass.placementGroup, type: .appPreview
                )
                guard files.isEmpty == false || current.isEmpty == false else { continue }

                plans.append(ChangePlan.PreviewPlan(
                    locale: locale,
                    deviceClass: deviceClass,
                    localFiles: files,
                    library: LibraryPlanner.slot(
                        files: files.map(\.libraryFile), current: current, record: record,
                        group: deviceClass.placementGroup, type: .appPreview
                    )
                ))
            }
        }
        return plans
    }

    // MARK: - Languages that show the source language's

    /// The art folder without the languages that show the source language's
    /// art. Their placements still plan, so a push takes them off.
    private static func usedCreative(_ folder: CreativeFolder, config: ProjectConfig) -> CreativeFolder {
        var used = folder
        for locale in config.creativeSources.keys {
            used.files[locale] = nil
        }
        return used
    }

    /// The files a tick leaves out, in language order.
    static func unusedFiles(in local: VersionContent, config: ProjectConfig) -> [ChangePlan.UnusedFile] {
        var unused: [ChangePlan.UnusedFile] = []
        for locale in config.writtenLocales.sorted() {
            for deviceClass in config.resolvedDeviceClasses
                where config.usesSourceScreenshots(locale: locale, deviceClassID: deviceClass.id) {
                unused += local.screenshots(locale: locale, deviceClassID: deviceClass.id).map {
                    .init(locale: locale, slot: .screenshots(deviceClass), url: $0.url, fileName: $0.fileName)
                }
            }
            guard config.creativeSource(locale: locale) != nil else { continue }
            for role in CreativeRole.allCases {
                unused += (local.creativeFolder.files[locale]?[role] ?? []).map {
                    .init(locale: locale, slot: .creative(role), url: $0.url, fileName: $0.fileName)
                }
            }
        }
        return unused
    }

    /// Placements whose asset App Store Connect is still processing, in the
    /// slots that change. A plan worked out from them can change once they
    /// finish.
    public static func stillArriving(in plan: ChangePlan) -> [RemotePlacement] {
        let slots = plan.screenshotPlans.map(\.library) + plan.previewPlans.map(\.library)
            + plan.creativePlans.map(\.library)
        return slots.filter { $0.isUnchanged == false }.flatMap(LibraryPlanner.stillArriving)
    }

    // MARK: - What the version's state refuses

    private static func blocked(
        textChanges: [ChangePlan.TextChange],
        screenshotPlans: [ChangePlan.ScreenshotPlan],
        changingPreviews: Int = 0,
        remote: RemoteListing
    ) -> [ChangePlan.Blocked] {
        var blocked: [ChangePlan.Blocked] = []

        // Apple's own word for the state, such as IN_REVIEW, which stays as it
        // is. Only the stand-in for a state nobody sent translates.
        let state = remote.versionState?.rawValue
            ?? String(localized: "an unknown state", bundle: .module)

        let versionFields = textChanges.filter { $0.isAppInfoField == false }
        if versionFields.isEmpty == false, remote.canEditText == false {
            blocked.append(.init(
                reason: LocalizedStringResource("""
                Version \(remote.versionString) is \(state) and does not accept text changes.
                """, bundle: .here),
                affects: LocalizedStringResource("\(versionFields.count) text changes", bundle: .here),
                cause: .versionStatus,
                parts: [.appInformation]
            ))
        }

        let appInfoFields = textChanges.filter(\.isAppInfoField)
        if appInfoFields.isEmpty == false, remote.canEditNameAndSubtitle == false {
            blocked.append(.init(
                reason: LocalizedStringResource("""
                The app information is not editable. The name and the subtitle are fixed \
                until a new version is in Prepare for Submission.
                """, bundle: .here),
                affects: LocalizedStringResource("\(appInfoFields.count) changes", bundle: .here),
                cause: .versionStatus,
                parts: [.appInformation]
            ))
        }

        // Previews count with the screenshot sets: they go out in the same part.
        let changingSets = screenshotPlans.count(where: \.changesAnything) + changingPreviews
        if changingSets > 0, remote.canEditScreenshots == false {
            blocked.append(.init(
                reason: LocalizedStringResource("""
                Version \(remote.versionString) is \(state) and does not accept screenshots.
                """, bundle: .here),
                affects: LocalizedStringResource(
                    "\(changingSets) screenshot sets", bundle: .here
                ),
                cause: .versionStatus,
                parts: [.screenshots]
            ))
        }
        return blocked
    }
}
