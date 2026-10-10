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
        let screenshots = ScreenshotFolder.load(from: project.screenshotsURL(.version(version)))

        return VersionContent(
            versionString: version,
            appInformation: information,
            unreadableInformation: unreadable,
            screenshots: screenshots.screenshots,
            screenshotLocales: screenshots.locales,
            emptiedScreenshotSets: screenshots.emptied,
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

    // MARK: - Directory reading

    private static func jsonFiles(in directory: URL) -> [URL] {
        DirectoryListing.entries(in: directory)
            .filter { DirectoryListing.isDirectory($0) == false && $0.pathExtension.lowercased() == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}
