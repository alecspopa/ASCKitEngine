import Foundation

/// Everything App Store Connect currently holds for one version of one app.
///
/// Assembled from several calls, so that everything above this reads one value
/// instead of walking Apple's relationship graph again.
public struct RemoteListing: Sendable {
    public let appID: String
    public let appName: String?
    public let bundleID: String

    /// Nil when no app information is editable, which means the name and the
    /// subtitle cannot be changed until a new version exists.
    public let appInfoID: String?
    public let appInfoState: AppInfoState?

    public let versionID: String
    public let versionString: String
    public let versionState: AppVersionState?

    /// The platform of the version this listing was read from, which is the
    /// platform of the app for an app on one platform. It says which device
    /// classes the store takes pictures for, so a Mac app is not asked for
    /// iPhone ones.
    public let versionPlatform: Platform?

    /// The version on sale, on the platform of this listing. Nil before the
    /// first release.
    public let releasedVersionString: String?

    /// The version after the one on sale: the one being written or in review.
    /// Nil when nothing comes after the release. An app holds one of each at
    /// most, so a version folder between the two never reached the store.
    public let pendingVersionString: String?

    /// Name, subtitle and privacy policy, keyed by locale.
    public let appInfoLocalizations: [String: RemoteLocalization]

    /// Description, keywords, what's new and the rest, keyed by locale.
    public let versionLocalizations: [String: RemoteLocalization]

    public let screenshotSets: [RemoteScreenshotSet]

    /// The library assets placed on each language of this version, in the
    /// store's order within each language. Empty unless the read asked for them.
    public let placements: [RemotePlacement]

    /// What the version on sale says. Nil when nobody asked for it.
    public let live: LiveTexts?

    public init(
        appID: String,
        appName: String?,
        bundleID: String,
        appInfoID: String?,
        appInfoState: AppInfoState?,
        versionID: String,
        versionString: String,
        versionState: AppVersionState?,
        versionPlatform: Platform? = nil,
        releasedVersionString: String? = nil,
        pendingVersionString: String? = nil,
        appInfoLocalizations: [String: RemoteLocalization],
        versionLocalizations: [String: RemoteLocalization],
        screenshotSets: [RemoteScreenshotSet],
        placements: [RemotePlacement] = [],
        live: LiveTexts? = nil
    ) {
        self.appID = appID
        self.appName = appName
        self.bundleID = bundleID
        self.appInfoID = appInfoID
        self.appInfoState = appInfoState
        self.versionID = versionID
        self.versionString = versionString
        self.versionState = versionState
        self.versionPlatform = versionPlatform
        self.releasedVersionString = releasedVersionString
        self.pendingVersionString = pendingVersionString
        self.appInfoLocalizations = appInfoLocalizations
        self.versionLocalizations = versionLocalizations
        self.screenshotSets = screenshotSets
        self.placements = placements
        self.live = live
    }

    /// Every locale App Store Connect knows about for this app, which is the
    /// authoritative answer to what codes it accepts.
    public var locales: [String] {
        Set(appInfoLocalizations.keys).union(versionLocalizations.keys).sorted()
    }

    public var canEditText: Bool { versionState?.acceptsTextChanges ?? false }
    public var canEditScreenshots: Bool { versionState?.acceptsScreenshotChanges ?? false }
    public var canEditNameAndSubtitle: Bool { appInfoState?.isEditable ?? false }
}

/// The words of the version on sale, which a person compares a new version with.
///
/// Empty before the first release. Every word of a first version is new.
public struct LiveTexts: Sendable {
    public let versionString: String?

    /// Name, subtitle and privacy policy of the live app information.
    public let appInfoLocalizations: [String: RemoteLocalization]

    public let versionLocalizations: [String: RemoteLocalization]

    public init(
        versionString: String?,
        appInfoLocalizations: [String: RemoteLocalization],
        versionLocalizations: [String: RemoteLocalization]
    ) {
        self.versionString = versionString
        self.appInfoLocalizations = appInfoLocalizations
        self.versionLocalizations = versionLocalizations
    }
}

/// One language's values, with the App Store Connect id needed to write them.
public struct RemoteLocalization: Sendable {
    public let id: String
    public let locale: String
    public let values: [String: String]

    public init(id: String, locale: String, values: [String: String]) {
        self.id = id
        self.locale = locale
        self.values = values
    }
}

public struct RemoteScreenshotSet: Sendable {
    public let id: String
    public let locale: String
    public let displayType: ScreenshotDisplayType
    public let screenshots: [RemoteScreenshot]

    public init(
        id: String,
        locale: String,
        displayType: ScreenshotDisplayType,
        screenshots: [RemoteScreenshot]
    ) {
        self.id = id
        self.locale = locale
        self.displayType = displayType
        self.screenshots = screenshots
    }
}

/// One screenshot of an old set, as much as the record's pairing reads.
public struct RemoteScreenshot: Sendable {
    public let id: String
    public let fileName: String?
    public let fileSize: Int?
    public let sourceFileChecksum: String?

    public init(id: String, fileName: String?, fileSize: Int?, sourceFileChecksum: String?) {
        self.id = id
        self.fileName = fileName
        self.fileSize = fileSize
        self.sourceFileChecksum = sourceFileChecksum
    }
}
