import Foundation

/// Reads a version folder into memory. It reports what is there and judges
/// nothing; that is the validator's job.
public enum ContentStore {
    public static func load(version: String, in project: Project) throws -> VersionContent {
        let versionURL = project.versionURL(version)
        guard FileManager.default.fileExists(atPath: versionURL.path) else {
            throw ProjectError.noSuchVersion(version)
        }

        let (information, unreadable) = loadAppInformation(version: version, in: project)
        let (screenshots, locales) = loadScreenshots(version: version, in: project)

        return VersionContent(
            versionString: version,
            appInformation: information,
            unreadableInformation: unreadable,
            screenshots: screenshots,
            screenshotLocales: locales,
            informationFolderName: project.informationURL(version: version).lastPathComponent,
            previewFolder: PreviewFolder.load(from: project.previewsURL(version: version)),
            creativeFolder: CreativeFolder.load(from: project.creativeURL(version: version))
        )
    }

    // MARK: - App information

    private static func loadAppInformation(
        version: String,
        in project: Project
    ) -> (copy: [String: AppInformation], unreadable: [String: String]) {
        let informationURL = project.informationURL(version: version)
        var copy: [String: AppInformation] = [:]
        var unreadable: [String: String] = [:]

        for file in jsonFiles(in: informationURL) {
            let locale = file.deletingPathExtension().lastPathComponent
            do {
                var loaded = try JSONDecoder().decode(AppInformation.self, from: Data(contentsOf: file))
                // The file name wins. A locale field that disagrees with it is
                // reported by the validator rather than silently followed.
                if loaded.locale.isEmpty { loaded.locale = locale }
                copy[locale] = loaded
            } catch {
                unreadable[locale] = "\(error)"
            }
        }
        return (copy, unreadable)
    }

    // MARK: - Screenshots

    private static func loadScreenshots(
        version: String,
        in project: Project
    ) -> (screenshots: [ScreenshotSlot: [ScreenshotFile]], locales: Set<String>) {
        let root = project.screenshotsURL(version: version)
        var screenshots: [ScreenshotSlot: [ScreenshotFile]] = [:]
        var locales: Set<String> = []

        for localeDirectory in DirectoryListing.directories(in: root) {
            let locale = localeDirectory.lastPathComponent
            locales.insert(locale)

            for deviceDirectory in DirectoryListing.directories(in: localeDirectory) {
                let slot = ScreenshotSlot(
                    locale: locale,
                    deviceClassID: deviceDirectory.lastPathComponent
                )
                screenshots[slot] = DirectoryListing.files(in: deviceDirectory, keys: imageKeys).map(ImageInspector.inspect)
            }
        }
        return (screenshots, locales)
    }

    // MARK: - Directory reading

    private static let imageKeys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey]

    private static func jsonFiles(in directory: URL) -> [URL] {
        DirectoryListing.entries(in: directory)
            .filter { DirectoryListing.isDirectory($0) == false && $0.pathExtension.lowercased() == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}
