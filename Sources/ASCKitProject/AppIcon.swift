import Foundation

/// Where the app's icon is, as something that can be shown.
///
/// The Xcode project already holds the icon, so a window on a listing can show
/// the app rather than a grey box with a folder name under it.
///
/// In the package rather than in the app, so anything that names a project
/// names it the same way. Finding is here, and so is reading an Icon Composer
/// document in `IconComposerDocument`. Drawing is not: the command line tool
/// has no window and nothing it does needs a picture.
public enum AppIcon {
    /// What Xcode calls the icon when a project says nothing.
    public static let defaultName = "AppIcon"

    /// An Icon Composer document, and an icon set. A project moving to Icon
    /// Composer keeps its icon set for older releases, so both can be there.
    ///
    /// Both are carried rather than one, because a caller draws the Icon
    /// Composer one and falls back to the icon set when the document holds
    /// nothing it can read.
    public struct Found: Sendable, Hashable {
        /// The `.icon` file. It holds the layers an icon is built from rather
        /// than a picture of one, which `IconComposerDocument` reads.
        public let iconComposerURL: URL?

        /// The largest image in the `.appiconset`. Anything can draw this.
        public let imageURL: URL?

        public init(iconComposerURL: URL?, imageURL: URL?) {
            self.iconComposerURL = iconComposerURL
            self.imageURL = imageURL
        }

        public var isEmpty: Bool { iconComposerURL == nil && imageURL == nil }
    }

    /// Folders that hold no artwork and are expensive to walk.
    private static let skipped: Set<String> = [
        ".build", "DerivedData", "Pods", "Carthage", "node_modules", "build", "vendor"
    ]

    /// Folders that are one icon rather than a place icons are kept. Nothing
    /// worth finding is inside either of them.
    private static let leafExtensions: Set<String> = ["icon", "appiconset"]

    /// How far under the folder to look. An asset catalog sits a folder or two
    /// below the repository root. Anything deeper than this is somebody else's
    /// checkout rather than this app's artwork.
    private static let maximumDepth = 4

    /// The icon the target names, in whichever forms the project keeps it.
    ///
    /// Nil when the project keeps neither.
    public static func find(in folderURL: URL, named name: String? = nil) -> Found? {
        let base = name ?? defaultName
        let document = "\(base).icon"
        let iconSet = "\(base).appiconset"

        let folders = folders(named: [document, iconSet], under: folderURL)
        let found = Found(
            iconComposerURL: folders[document],
            imageURL: folders[iconSet].flatMap(largestImage)
        )
        return found.isEmpty ? nil : found
    }

    /// The icon of the app a listing is for, given the folder holding both.
    ///
    /// Reads the Xcode project to learn which target and which icon name, so a
    /// caller with a folder needs nothing else. Pass no bundle identifier when
    /// there is none to hand, and the only app in the project answers.
    public static func find(in folderURL: URL, forBundleID bundleID: String?) -> Found? {
        guard
            let projectURL = XcodeProject.find(in: folderURL),
            let xcode = try? XcodeProject.read(at: projectURL)
        else {
            return nil
        }
        return find(in: folderURL, named: xcode.app(forBundleID: bundleID)?.iconName)
    }

    // MARK: - Looking

    /// Breadth first, so a shallow match wins over a deep one. A repository with
    /// a sample app inside it should show its own icon, not the sample's.
    ///
    /// One walk for both names. Walking twice would read every folder in the
    /// repository twice to answer one question.
    private static func folders(named names: [String], under folderURL: URL) -> [String: URL] {
        var wanted = Set(names)
        var found: [String: URL] = [:]
        var level = [folderURL]

        for _ in 0 ..< maximumDepth {
            var next: [URL] = []
            for folder in level {
                for entry in directories(in: folder) {
                    let name = entry.lastPathComponent
                    if wanted.contains(name) {
                        // Built from the name rather than handed back as found.
                        // `contentsOfDirectory` marks a directory with a
                        // trailing slash, and a caller comparing two URLs
                        // should not have to know that.
                        found[name] = folder.appending(path: name)
                        wanted.remove(name)
                        if wanted.isEmpty { return found }
                        continue
                    }
                    guard skipped.contains(name) == false else { continue }
                    guard leafExtensions.contains(entry.pathExtension) == false else { continue }
                    next.append(entry)
                }
            }
            guard next.isEmpty == false else { return found }
            level = next
        }
        return found
    }

    private static func directories(in folder: URL) -> [URL] {
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        return entries
            .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// The largest image in an icon set, because an icon set holds the same
    /// artwork at every size a device asks for.
    ///
    /// Measured rather than weighed. A dark variant of the same icon can be the
    /// larger file while being the smaller picture.
    private static func largestImage(in iconSet: URL) -> URL? {
        let entries = (try? FileManager.default.contentsOfDirectory(
            at: iconSet,
            includingPropertiesForKeys: [.fileSizeKey],
            options: [.skipsHiddenFiles]
        )) ?? []

        return entries
            .filter { $0.pathExtension.lowercased() == "png" }
            .map { (url: $0, size: ImageInspector.inspect(url: $0)) }
            .filter { $0.size.pixelWidth != nil }
            .max { first, second in area(first.size) < area(second.size) }
            .map(\.url)
    }

    private static func area(_ file: ScreenshotFile) -> Int {
        (file.pixelWidth ?? 0) * (file.pixelHeight ?? 0)
    }
}
