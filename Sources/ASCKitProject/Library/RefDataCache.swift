import ASCKitAPI
import Foundation

/// The last reference data App Store Connect sent, kept in the project's
/// cache so that a check without a network connection uses Apple's own sizes.
public enum RefDataCache {
    private static let file = CacheFile<AssetLibraryRefData>(path: "asset-library-refdata.json", atomic: true)

    public static func url(in project: Project) -> URL {
        file.url(in: project)
    }

    /// Nil when nothing has read it yet, or when the file is damaged. Either
    /// way the built-in sizes apply.
    public static func load(in project: Project) -> AssetLibraryRefData? {
        file.load(in: project)
    }

    public static func save(_ refData: AssetLibraryRefData, in project: Project) throws {
        try file.save(refData, in: project)
    }
}
