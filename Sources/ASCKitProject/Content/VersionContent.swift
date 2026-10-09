import Foundation

/// Which screenshot set a folder of images belongs to.
public struct ScreenshotSlot: Sendable, Hashable {
    public let locale: String
    public let deviceClassID: String

    public init(locale: String, deviceClassID: String) {
        self.locale = locale
        self.deviceClassID = deviceClassID
    }
}

/// Everything one version folder holds, read from disk and not yet checked.
///
/// This says what is there, including things that should not be. The validator
/// decides what is wrong; keeping the two apart means the app can show a
/// project that is broken rather than refusing to open it.
public struct VersionContent: Sendable {
    public let versionString: String

    /// Keyed by locale. Includes files for locales the configuration does not
    /// list, because a stray file is worth reporting.
    public let appInformation: [String: AppInformation]

    /// Files that could not be read at all, with the reason.
    public let unreadableInformation: [String: String]

    public let screenshots: [ScreenshotSlot: [ScreenshotFile]]

    /// Locale folders found under screenshots, whatever the configuration says.
    public let screenshotLocales: Set<String>

    /// What the folder holding the text is called here: `version-data`, or the
    /// `app-information` an older project has. Carried so a problem names the
    /// path a person will find rather than the one ASCKit would write.
    public let informationFolderName: String

    /// The app previews, in folders laid out like the screenshots.
    public let previewFolder: PreviewFolder

    /// The product page header and search results art of each language.
    public let creativeFolder: CreativeFolder

    public init(
        versionString: String,
        appInformation: [String: AppInformation],
        unreadableInformation: [String: String],
        screenshots: [ScreenshotSlot: [ScreenshotFile]],
        screenshotLocales: Set<String>,
        informationFolderName: String = Project.informationFolderName,
        previewFolder: PreviewFolder = PreviewFolder(),
        creativeFolder: CreativeFolder = CreativeFolder()
    ) {
        self.versionString = versionString
        self.appInformation = appInformation
        self.unreadableInformation = unreadableInformation
        self.screenshots = screenshots
        self.screenshotLocales = screenshotLocales
        self.informationFolderName = informationFolderName
        self.previewFolder = previewFolder
        self.creativeFolder = creativeFolder
    }

    public func previews(locale: String, deviceClassID: String) -> [PreviewFile] {
        previewFolder.previews(locale: locale, deviceClassID: deviceClassID)
    }

    public func screenshots(locale: String, deviceClassID: String) -> [ScreenshotFile] {
        screenshots[ScreenshotSlot(locale: locale, deviceClassID: deviceClassID)] ?? []
    }

    /// How many images this device class holds, across every language.
    ///
    /// Unlisting a device class is one line in `asckit.json` and it answers for
    /// every language at once, so the question it asks counts them all.
    public func screenshotCount(deviceClassID: String) -> Int {
        screenshots
            .filter { $0.key.deviceClassID == deviceClassID }
            .values
            .reduce(0) { $0 + $1.count }
    }
}
