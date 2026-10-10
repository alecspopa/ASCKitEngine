import Foundation

/// The screenshots under one place, read and not yet checked.
///
///     <root>/<locale>/<device class>/01-hero-iPhone-6.9-en_US.png
///
/// The same walk for a version, a treatment and a custom product page. Only
/// the root and the folder names to skip differ.
public struct ScreenshotFolder: Sendable {
    public var screenshots: [ScreenshotSlot: [ScreenshotFile]] = [:]

    /// Every language folder found, an empty one too.
    public var locales: Set<String> = []

    /// Sets that hold the marker a remove leaves when it empties a set on
    /// purpose. Only these take App Store Connect's images off on a push. A
    /// set that is empty because a read wrote no files leaves them alone.
    public var emptied: Set<ScreenshotSlot> = []

    /// Hidden, so a listing of the set never shows it.
    public static let emptiedMarkerName = ".asckit-emptied"

    public init() {}

    /// `skipping` names folders beside the language folders that hold
    /// something else, such as `previews` in a treatment.
    public static func load(from root: URL, skipping: Set<String> = []) -> ScreenshotFolder {
        var folder = ScreenshotFolder()
        for localeDirectory in DirectoryListing.directories(in: root)
            where skipping.contains(localeDirectory.lastPathComponent) == false {
            let locale = localeDirectory.lastPathComponent
            folder.locales.insert(locale)

            for deviceDirectory in DirectoryListing.directories(in: localeDirectory) {
                let slot = ScreenshotSlot(locale: locale, deviceClassID: deviceDirectory.lastPathComponent)
                folder.screenshots[slot] = DirectoryListing.files(in: deviceDirectory, keys: imageKeys)
                    .map(ImageInspector.inspect)
                if FileManager.default.fileExists(atPath: deviceDirectory.appending(path: emptiedMarkerName).path) {
                    folder.emptied.insert(slot)
                }
            }
        }
        return folder
    }

    static let imageKeys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey]
}
