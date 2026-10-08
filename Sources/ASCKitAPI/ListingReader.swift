import Foundation

public extension ASCClient {
    /// Reads one version's whole listing.
    ///
    /// Locales are fetched concurrently because a listing in eleven languages
    /// is otherwise eleven round trips waiting on each other.
    ///
    /// No platform by default. Asking for the iOS versions of a Mac app gives
    /// an empty list, and an app with a version in front of the reviewer then
    /// reads as an app with no versions at all.
    func listing(
        bundleID: String,
        versionString: String? = nil,
        platform: Platform? = nil,
        includeScreenshots: Bool = true,
        includeLiveTexts: Bool = false
    ) async throws -> RemoteListing {
        guard let app = try await app(bundleID: bundleID) else {
            throw ListingError.noSuchApp(bundleID: bundleID)
        }

        // Fetched once and picked from, rather than asking twice.
        let versions = try await appStoreVersions(appID: app.id, platform: platform)
        guard let version = pickVersion(from: versions, versionString: versionString) else {
            throw ListingError.noSuchVersion(versionString: versionString, bundleID: bundleID)
        }

        let platformVersions = versions.filter {
            $0.attributes?.platform == version.attributes?.platform
        }

        let appInfos = try await appInfos(appID: app.id)
        let appInfo = appInfos.first { $0.attributes?.state?.isEditable == true }

        // With nothing editable, the plan still compares against the name the
        // store holds. Compared against nothing, every field reads as new.
        async let infoLocalizations = readAppInfoLocalizations(
            appInfoID: (appInfo ?? Self.currentAppInfo(in: appInfos))?.id
        )
        async let versionLocalizations = readVersionLocalizations(versionID: version.id)
        async let live = includeLiveTexts
            ? readLiveTexts(
                version: platformVersions.first { $0.attributes?.appVersionState == .readyForDistribution },
                appInfo: appInfos.first { $0.attributes?.state == .readyForDistribution }
            )
            : nil

        let localizations = try await versionLocalizations
        async let sets = includeScreenshots
            ? readScreenshotSets(localizations: localizations)
            : []
        // The old sets are read only so that the record can pair their
        // screenshots with the placements that took them over.
        let placements = includeScreenshots
            ? try await readPlacements(localizations.map { (.versionLocalization(id: $0.id), $0.locale) })
            : []

        return try await RemoteListing(
            appID: app.id,
            appName: app.attributes?.name,
            bundleID: bundleID,
            appInfoID: appInfo?.id,
            appInfoState: appInfo?.attributes?.state,
            versionID: version.id,
            versionString: version.attributes?.versionString ?? versionString ?? "",
            versionState: version.attributes?.appVersionState,
            versionPlatform: version.attributes?.platform,
            releasedVersionString: Self.released(in: platformVersions),
            pendingVersionString: Self.pending(in: platformVersions),
            appInfoLocalizations: infoLocalizations,
            versionLocalizations: Dictionary(
                uniqueKeysWithValues: localizations.map { ($0.locale, $0) }
            ),
            screenshotSets: sets,
            placements: placements,
            live: live
        )
    }

    /// The words of the version on sale. Its app information is the live one,
    /// because the name in the editable one is the name about to go out.
    private func readLiveTexts(
        version: Resource<AppStoreVersionAttributes>?,
        appInfo: Resource<AppInfoAttributes>?
    ) async throws -> LiveTexts {
        guard let version else {
            return LiveTexts(versionString: nil, appInfoLocalizations: [:], versionLocalizations: [:])
        }

        async let infoLocalizations = readAppInfoLocalizations(appInfoID: appInfo?.id)
        let localizations = try await readVersionLocalizations(versionID: version.id)

        return try await LiveTexts(
            versionString: version.attributes?.versionString,
            appInfoLocalizations: infoLocalizations,
            versionLocalizations: Dictionary(
                uniqueKeysWithValues: localizations.map { ($0.locale, $0) }
            )
        )
    }

    /// Prefers a version that still accepts changes, and falls back to any
    /// version so that pull can report a live listing rather than refuse to
    /// look at it.
    private func pickVersion(
        from versions: [Resource<AppStoreVersionAttributes>],
        versionString: String?
    ) -> Resource<AppStoreVersionAttributes>? {
        let candidates = versionString.map { wanted in
            versions.filter { $0.attributes?.versionString == wanted }
        } ?? versions

        return candidates.first { $0.attributes?.appVersionState?.acceptsTextChanges == true }
            ?? candidates.first
    }

    /// The one version on sale.
    static func released(in versions: [Resource<AppStoreVersionAttributes>]) -> String? {
        versions.first { $0.attributes?.appVersionState == .readyForDistribution }?
            .attributes?.versionString
    }

    /// The one version that is neither on sale nor replaced by a newer one.
    static func pending(in versions: [Resource<AppStoreVersionAttributes>]) -> String? {
        let done: Set<AppVersionState> = [.readyForDistribution, .replacedWithNewVersion]
        return versions.first {
            guard let state = $0.attributes?.appVersionState else { return false }
            return done.contains(state) == false
        }?.attributes?.versionString
    }

    /// The newest app information that is not editable. One in review holds
    /// newer words than the live one, and a replaced one holds old words.
    static func currentAppInfo(
        in infos: [Resource<AppInfoAttributes>]
    ) -> Resource<AppInfoAttributes>? {
        let current = infos.filter { $0.attributes?.state != .replacedWithNewInfo }
        return current.first { $0.attributes?.state != .readyForDistribution }
            ?? current.first
    }

    private func readAppInfoLocalizations(appInfoID: String?) async throws -> [String: RemoteLocalization] {
        guard let appInfoID else { return [:] }

        let resources = try await appInfoLocalizations(appInfoID: appInfoID)
        return Dictionary(uniqueKeysWithValues: resources.compactMap { resource in
            guard let attributes = resource.attributes, let locale = attributes.locale else { return nil }
            var values: [String: String] = [:]
            values["name"] = attributes.name
            values["subtitle"] = attributes.subtitle
            values["privacyPolicyUrl"] = attributes.privacyPolicyUrl
            return (locale, RemoteLocalization(id: resource.id, locale: locale, values: values))
        })
    }

    private func readVersionLocalizations(versionID: String) async throws -> [RemoteLocalization] {
        let resources = try await versionLocalizations(versionID: versionID)
        return resources.compactMap { resource in
            guard let attributes = resource.attributes, let locale = attributes.locale else { return nil }
            var values: [String: String] = [:]
            values["description"] = attributes.description
            values["keywords"] = attributes.keywords
            values["whatsNew"] = attributes.whatsNew
            values["promotionalText"] = attributes.promotionalText
            values["marketingUrl"] = attributes.marketingUrl
            values["supportUrl"] = attributes.supportUrl
            return RemoteLocalization(id: resource.id, locale: locale, values: values)
        }
    }

    private func readScreenshotSets(
        localizations: [RemoteLocalization]
    ) async throws -> [RemoteScreenshotSet] {
        let outcomes = await withTaskGroup(
            of: Result<[RemoteScreenshotSet], any Error>.self
        ) { group in
            for localization in localizations {
                group.addTask {
                    await Self.captured { try await readScreenshotSets(for: localization) }
                }
            }
            var collected: [Result<[RemoteScreenshotSet], any Error>] = []
            for await outcome in group {
                collected.append(outcome)
            }
            return collected
        }

        let all = try Self.unwrap(outcomes).flatMap(\.self)
        return all.sorted {
            ($0.locale, $0.displayType.rawValue) < ($1.locale, $1.displayType.rawValue)
        }
    }

    private func readScreenshotSets(
        for localization: RemoteLocalization
    ) async throws -> [RemoteScreenshotSet] {
        let sets = try await screenshotSets(localizationID: localization.id)
        return try await readScreenshots(in: sets, locale: localization.locale)
    }

    /// The images of every set in a list, read together.
    ///
    /// Shared by a version's languages and a treatment's, which hold the same
    /// sets under a different parent.
    func readScreenshots(
        in sets: [Resource<ScreenshotSetAttributes>],
        locale: String
    ) async throws -> [RemoteScreenshotSet] {
        let outcomes = await withTaskGroup(
            of: Result<RemoteScreenshotSet?, any Error>.self
        ) { group in
            for set in sets {
                group.addTask {
                    await Self.captured {
                        guard let displayType = set.attributes?.screenshotDisplayType else { return nil }
                        let shots = try await screenshots(setID: set.id)
                        return RemoteScreenshotSet(
                            id: set.id,
                            locale: locale,
                            displayType: displayType,
                            screenshots: shots.map { shot in
                                RemoteScreenshot(
                                    id: shot.id,
                                    fileName: shot.attributes?.fileName,
                                    fileSize: shot.attributes?.fileSize,
                                    sourceFileChecksum: shot.attributes?.sourceFileChecksum
                                )
                            }
                        )
                    }
                }
            }
            var collected: [Result<RemoteScreenshotSet?, any Error>] = []
            for await outcome in group {
                collected.append(outcome)
            }
            return collected
        }

        return try Self.unwrap(outcomes).compactMap(\.self)
    }

    /// What the store serves for an image it holds. An image it is still
    /// working on has no address yet.
    static func preview(of asset: ImageAsset?) -> RemoteImage? {
        guard let asset, let template = asset.templateUrl else { return nil }
        return RemoteImage(template: template, width: asset.width, height: asset.height)
    }

    /// Runs one child of a group and keeps whatever it did, win or lose.
    ///
    /// A child that throws would cancel its siblings, and a cancelled sibling
    /// then reports `cancelled` rather than the reason for it. Reading eleven
    /// languages is short enough to let every one of them finish and answer
    /// with the failure that started it.
    static func captured<Value: Sendable>(
        _ work: () async throws -> Value
    ) async -> Result<Value, any Error> {
        do {
            return try await .success(work())
        } catch {
            return .failure(error)
        }
    }

    /// Everything that worked, or the failure worth showing.
    static func unwrap<Value>(_ outcomes: [Result<Value, any Error>]) throws -> [Value] {
        let failures = outcomes.compactMap(\.failure)
        if let error = failures.mostTelling { throw error }
        return outcomes.compactMap(\.success)
    }
}

extension Result {
    var success: Success? {
        guard case let .success(value) = self else { return nil }
        return value
    }

    var failure: Failure? {
        guard case let .failure(error) = self else { return nil }
        return error
    }
}

public enum ListingError: Error, CustomLocalizedStringResourceConvertible {
    case noSuchApp(bundleID: String)
    case noSuchVersion(versionString: String?, bundleID: String)

    public var localizedStringResource: LocalizedStringResource {
        switch self {
        case let .noSuchApp(bundleID):
            LocalizedStringResource("""
            App Store Connect has no app with the bundle id \(bundleID). Check the id, and \
            check that the key's team owns the app.
            """, bundle: .here)
        case let .noSuchVersion(versionString, bundleID):
            if let versionString {
                LocalizedStringResource("\(versionString) is not a version of \(bundleID).", bundle: .here)
            } else {
                LocalizedStringResource("""
                \(bundleID) has no version in App Store Connect yet. ASCKit reads and writes \
                the listing of one version, so there is nothing there to read. This can wait \
                until the app has its first version. Everything written here stays on disk.
                """, bundle: .here)
            }
        }
    }
}

extension ListingError: CustomStringConvertible {
    public var description: String { String(localized: localizedStringResource) }
}
