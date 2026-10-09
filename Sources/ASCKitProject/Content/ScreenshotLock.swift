import ASCKitAPI
import Foundation

/// A version folder that App Store Connect takes no more screenshots for.
///
/// A released version never takes a new screenshot. A file put in its folder
/// only waits there for a push that App Store Connect refuses. So the window,
/// the terminal and the MCP tools all ask this before they file one, and all
/// refuse with the same sentence.
public struct ScreenshotLock: Error, Sendable, Equatable {
    /// The version folder a screenshot would go into.
    public let version: String

    /// Apple's own word for the state of that version, such as
    /// READY_FOR_DISTRIBUTION. Nil when App Store Connect sent none.
    public let state: String?

    /// The version App Store Connect is on, which is the version that can take
    /// the screenshots when it is not this one.
    public let storeVersion: String

    public init(version: String, state: String?, storeVersion: String) {
        self.version = version
        self.state = state
        self.storeVersion = storeVersion
    }

    /// The lock on a version folder, or nil when it takes screenshots.
    ///
    /// Nil with no listing. Filing goes ahead offline, and the push refuses
    /// later. The same rule as the push plan, plus the release: a folder for
    /// the version on sale is locked when App Store Connect has already moved
    /// on to the next one.
    public static func lock(version: String, listing: RemoteListing?) -> ScreenshotLock? {
        guard let listing else { return nil }

        if listing.versionString == version, listing.canEditScreenshots == false {
            return ScreenshotLock(
                version: version,
                state: listing.versionState?.rawValue,
                storeVersion: listing.versionString
            )
        }
        if listing.releasedVersionString == version {
            return ScreenshotLock(
                version: version,
                state: AppVersionState.readyForDistribution.rawValue,
                storeVersion: listing.versionString
            )
        }
        return nil
    }

    /// Throws the lock on a version folder, so a caller about to write can
    /// stop in one line.
    public static func refuse(version: String, listing: RemoteListing?) throws {
        if let lock = lock(version: version, listing: listing) { throw lock }
    }
}

extension ScreenshotLock: CustomLocalizedStringResourceConvertible {
    public var localizedStringResource: LocalizedStringResource {
        // Apple's own word for the state stays as it is, as in the push plan.
        let stateName = state ?? String(localized: "an unknown state", bundle: .module)

        // Whole sentences rather than one with a clause dropped into it. A
        // translator cannot place a clause that arrives already built.
        if storeVersion == version {
            return LocalizedStringResource("""
            Version \(version) is \(stateName) and does not accept screenshots. \
            Add a new version in App Store Connect first.
            """, bundle: .here)
        }
        return LocalizedStringResource("""
        Version \(version) is \(stateName) and does not accept screenshots. \
        Make the folder for version \(storeVersion) first.
        """, bundle: .here)
    }
}

/// English, because the terminal and the MCP tools print this.
extension ScreenshotLock: CustomStringConvertible {
    public var description: String { localizedStringResource.english }
}
