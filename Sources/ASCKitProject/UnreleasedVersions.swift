import ASCKitAPI
import Foundation

/// Version folders for a version App Store Connect never released.
///
/// An app holds at most one version on sale and one version after it. A
/// version string can change before release: 1.16 in App Store Connect becomes
/// 2.0, and the folder for 1.16 stays here with nothing on the store behind
/// it. So a folder newer than the release and older than the pending version
/// is a version that never shipped.
///
/// A folder older than the release is kept. It is the history of the app, and
/// `VersionSeed` finds old screenshots in it by checksum. A folder newer than
/// the pending version is kept too, because it is a release somebody plans.
public enum UnreleasedVersions {
    public static func folders(listing: RemoteListing, versions: [String]) -> [String] {
        guard let pending = listing.pendingVersionString else { return [] }
        let released = listing.releasedVersionString

        return versions.filter { name in
            guard name != listing.versionString, name != released else { return false }
            let afterRelease = released.map { isOlder($0, than: name) } ?? true
            return afterRelease && isOlder(name, than: pending)
        }
    }

    public static func folders(listing: RemoteListing, project: Project) throws -> [String] {
        try folders(listing: listing, versions: project.versionNames())
    }

    /// Moves the folders to the Trash, so a person can take one back. Returns
    /// the names of the folders it moved.
    @discardableResult
    public static func moveToTrash(listing: RemoteListing, in project: Project) throws -> [String] {
        let names = try folders(listing: listing, project: project)
        for name in names {
            try FileManager.default.trashItem(at: project.versionURL(name), resultingItemURL: nil)
        }
        return names
    }

    /// The same order `Project.versionNames()` uses, so 1.9 comes before 1.10.
    private static func isOlder(_ lhs: String, than rhs: String) -> Bool {
        lhs.compare(rhs, options: .numeric) == .orderedAscending
    }
}
