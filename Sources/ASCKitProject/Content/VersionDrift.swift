import ASCKitAPI
import Foundation

/// Where the version folders on disk and App Store Connect have stopped
/// agreeing.
///
/// App Store Connect moves on its own. Somebody adds a version in the web page,
/// or a release goes out and the next version opens behind it, and nothing on
/// disk hears about it. Everything that pushes then loads the folder named
/// after the version App Store Connect is on, so the first sign of a new
/// version is a run that stops with "there is no folder for 1.1" rather than
/// the news that the app has a new version at all.
///
/// This is the App Store Connect half of what `XcodeDrift` says about the
/// `.xcodeproj` beside the project.
public enum VersionDrift {
    public enum Outcome: Sendable, Equatable {
        /// There is a folder for the version App Store Connect is on.
        case agreed(version: String)

        /// App Store Connect is on a version with no folder here. `newest` is
        /// the newest folder there is, because that is the one a person
        /// recognises.
        case missingFolder(version: String, newest: String?)
    }

    public static func compare(listing: RemoteListing, versions: [String]) -> Outcome {
        guard versions.contains(listing.versionString) == false else {
            return .agreed(version: listing.versionString)
        }
        return .missingFolder(version: listing.versionString, newest: versions.last)
    }

    /// Reads the folders, so a caller holding a project and a listing needs
    /// nothing else.
    public static func compare(listing: RemoteListing, project: Project) throws -> Outcome {
        try compare(listing: listing, versions: project.versionNames())
    }
}

public extension VersionDrift.Outcome {
    /// The version App Store Connect is on, whichever outcome this is.
    var version: String {
        switch self {
        case let .agreed(version), let .missingFolder(version, _): version
        }
    }

    /// The version to make a folder for, or nil when there is nothing to make.
    var versionToCreate: String? {
        guard case let .missingFolder(version, _) = self else { return nil }
        return version
    }

    /// An error rather than a warning, unlike everything `XcodeDrift` reports.
    /// Xcode moving first is the normal way round and costs nothing. App Store
    /// Connect moving first stops a push dead, because there is no content to
    /// push for the version it would push to.
    func problem(versionsPath: String) -> Problem? {
        guard case let .missingFolder(version, newest) = self else { return nil }

        // Two whole sentences rather than one with a fragment dropped into it.
        // A translator cannot place a clause that arrives already built.
        let message = newest.map {
            LocalizedStringResource("""
            App Store Connect is on version \(version), and there is no folder for it. \
            The newest folder here is \($0).
            """, bundle: .here)
        } ?? LocalizedStringResource("""
        App Store Connect is on version \(version), and there is no folder for it. \
        There are no version folders here yet.
        """, bundle: .here)

        return Problem(
            severity: .error,
            area: .layout,
            message: message,
            fix: LocalizedStringResource(
                "Make \(versionsPath)/\(version) and write the app information for that version.",
                bundle: .here
            ),
            path: versionsPath,
            kind: .versionFolderMissingForStore
        )
    }
}
