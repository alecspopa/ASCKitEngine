import ASCKitAPI
import Foundation

/// Where the language list on disk and the one on App Store Connect have
/// stopped agreeing.
///
/// A listing is usually older than the project that reads it. An app ships in
/// eleven languages for a year before anybody puts it in files, and the
/// configuration a new project starts with lists one. Nothing on disk hears
/// about the other ten, so the window shows one language and the store shows
/// eleven.
///
/// What App Store Connect holds is the authoritative list. It skips a code it
/// does not recognise instead of refusing it, so a code taken from anywhere
/// else can look right and upload nothing.
///
/// This is the language half of what `VersionDrift` says about versions.
public enum LocaleDrift {
    public struct Outcome: Sendable, Equatable {
        /// Languages App Store Connect holds that the configuration leaves out.
        /// These are the ones worth bringing in, because they are already on
        /// the store and nothing here can see them.
        public let missingHere: [String]

        /// Languages the configuration lists that App Store Connect has never
        /// seen.
        ///
        /// A push writes nothing in them. ASCKit never makes a language on App
        /// Store Connect, so the page has to be made there first. Ignored
        /// languages are left out: those are the ones that are meant to have no
        /// page.
        public let missingThere: [String]

        public var agrees: Bool { missingHere.isEmpty && missingThere.isEmpty }

        public init(missingHere: [String], missingThere: [String]) {
            self.missingHere = missingHere
            self.missingThere = missingThere
        }
    }

    public static func compare(listing: RemoteListing, config: ProjectConfig) -> Outcome {
        compare(remote: listing.locales, config: config)
    }

    /// The same, for a caller holding the codes rather than the listing they
    /// came out of.
    public static func compare(remote: [String], config: ProjectConfig) -> Outcome {
        let there = Set(remote)
        return Outcome(
            missingHere: there.subtracting(config.locales).sorted(),
            missingThere: Set(config.writtenLocales).subtracting(there).sorted()
        )
    }
}
