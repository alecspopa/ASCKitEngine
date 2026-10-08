import Foundation

/// Reads a version folder into memory. It reports what is there and judges
/// nothing; that is the validator's job.
public enum ContentStore {
    /// Files that are not screenshots but turn up in screenshot folders anyway.
    private static let ignoredFileNames: Set<String> = [".DS_Store", "Thumbs.db"]

    public static func load(version: String, in project: Project) throws -> VersionContent {
        let versionURL = project.versionsURL.appending(path: version)
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

        for localeDirectory in directories(in: root) {
            let locale = localeDirectory.lastPathComponent
            locales.insert(locale)

            for deviceDirectory in directories(in: localeDirectory) {
                let slot = ScreenshotSlot(
                    locale: locale,
                    deviceClassID: deviceDirectory.lastPathComponent
                )
                screenshots[slot] = imageFiles(in: deviceDirectory).map(ImageInspector.inspect)
            }
        }
        return (screenshots, locales)
    }

    // MARK: - Directory reading

    private static func entries(in directory: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )) ?? []
    }

    /// `hasDirectoryPath` only looks for a trailing slash on the string, so it
    /// is not a reliable answer. Ask the file system.
    private static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
    }

    private static func directories(in directory: URL) -> [URL] {
        entries(in: directory)
            .filter(isDirectory)
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private static func jsonFiles(in directory: URL) -> [URL] {
        entries(in: directory)
            .filter { isDirectory($0) == false && $0.pathExtension.lowercased() == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Everything that is not a directory and not a known stray file. A file
    /// with the wrong extension is returned on purpose, so it can be reported
    /// rather than quietly skipped and then uploaded by something else.
    private static func imageFiles(in directory: URL) -> [URL] {
        entries(in: directory)
            .filter { isDirectory($0) == false }
            .filter { ignoredFileNames.contains($0.lastPathComponent) == false }
            .sorted { $0.lastPathComponent.compare($1.lastPathComponent, options: .numeric) == .orderedAscending }
    }
}
