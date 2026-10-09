import ASCKitAPI
import Foundation

/// The last reference data App Store Connect sent, kept in the project's
/// cache so that a check without a network connection uses Apple's own sizes.
public enum RefDataCache {
    public static func url(in project: Project) -> URL {
        project.cacheURL.appending(path: "asset-library-refdata.json")
    }

    /// Nil when nothing has read it yet, or when the file is damaged. Either
    /// way the built-in sizes apply.
    public static func load(in project: Project) -> AssetLibraryRefData? {
        guard let data = try? Data(contentsOf: url(in: project)) else { return nil }
        return try? JSONDecoder().decode(AssetLibraryRefData.self, from: data)
    }

    public static func save(_ refData: AssetLibraryRefData, in project: Project) throws {
        let url = url(in: project)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try ProjectJSON.write(refData, to: url, atomic: true)
    }
}
