import ASCKitAPI
import Foundation

/// A place that App Store Connect takes no screenshot for now: a released
/// version, a test in review or running, or a custom product page in review
/// or approved.
///
/// The window, the terminal and the MCP tools ask this before every write to
/// a set, and all refuse with the same sentence.
public enum ScreenshotPlaceLock: Error, Sendable, Equatable {
    case version(ScreenshotLock)
    /// A test folder, and Apple's own word for its state.
    case test(folder: String, state: String?)
    /// A page folder, and Apple's own word for its state.
    case page(folder: String, state: String?)

    /// The lock on a place, or nil when it takes screenshots.
    ///
    /// Nil when nothing was read about the place. Writing goes ahead offline,
    /// and the push refuses later, the same rule as `ScreenshotLock`.
    public static func lock(
        for place: LibraryContentPlace,
        listing: RemoteListing?,
        experiments: ExperimentSnapshot?,
        pages: CustomPageSnapshot?
    ) -> ScreenshotPlaceLock? {
        switch place {
        case let .version(version):
            return ScreenshotLock.lock(version: version, listing: listing).map(Self.version)
        case let .treatment(experiment, _):
            guard let test = experiments?.experiments.first(where: { $0.folder == experiment }),
                  test.isEditable == false
            else { return nil }
            return .test(folder: experiment, state: test.state)
        case let .customPage(folder):
            guard let page = pages?.page(folder: folder), page.isEditable == false else { return nil }
            return .page(folder: folder, state: page.state)
        }
    }

    /// Throws the lock on a place, so a caller about to write can stop in one
    /// line.
    public static func refuse(
        _ place: LibraryContentPlace,
        listing: RemoteListing?,
        experiments: ExperimentSnapshot?,
        pages: CustomPageSnapshot?
    ) throws {
        if let lock = lock(for: place, listing: listing, experiments: experiments, pages: pages) { throw lock }
    }
}

extension ScreenshotPlaceLock: CustomLocalizedStringResourceConvertible {
    public var localizedStringResource: LocalizedStringResource {
        switch self {
        case let .version(lock):
            return lock.localizedStringResource
        case let .test(folder, state):
            // Apple's own word for the state stays as it is, as in the push plan.
            let stateName = state ?? String(localized: "an unknown state", bundle: .module)
            return LocalizedStringResource("""
            The test \(folder) is \(stateName) on App Store Connect, so it takes no change. \
            Only a test in Prepare for Submission or Rejected takes images.
            """, bundle: .here)
        case let .page(folder, state):
            let stateName = state ?? String(localized: "an unknown state", bundle: .module)
            return LocalizedStringResource("""
            The custom product page \(folder) is \(stateName) on App Store Connect, so it takes \
            no change. Start a new version of the page in App Store Connect, then read again.
            """, bundle: .here)
        }
    }
}

/// English, because the terminal and the MCP tools print this.
extension ScreenshotPlaceLock: CustomStringConvertible {
    public var description: String { localizedStringResource.english }
}
