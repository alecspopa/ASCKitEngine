import ASCKitAPI
import Foundation

/// Taking the languages App Store Connect holds into a project.
///
/// An app usually ships in more languages than a project starts with. The
/// configuration a new project is scaffolded with lists one, and until the
/// other ten are in files nothing here can show them or push them.
///
/// The app's sidebar and `asckit pull --adopt-locales` both come here. The same
/// rule decides what can be taken in, the same words say why it cannot, and the
/// same files get written, so a project set up in the window and one set up on
/// the command line end up the same.
public enum LocaleAdoption {
    /// What taking the languages in would do.
    public struct Plan: Sendable, Equatable {
        /// The languages that would be added, sorted.
        public let locales: [String]

        /// The version folder their app information files would go in.
        public let version: String

        public init(locales: [String], version: String) {
            self.locales = locales
            self.version = version
        }
    }

    /// Why there is nothing to do, or why it cannot be done yet.
    public enum Refusal: Error, Sendable, Equatable, CustomLocalizedStringResourceConvertible {
        /// App Store Connect has not been read yet, so nothing here knows what
        /// it holds.
        case nothingReadYet

        case everythingIsAlreadyHere

        /// App Store Connect is on a version this project has no folder for.
        ///
        /// The files would go into the newest folder on disk, which is a
        /// different version, and a listing written into the wrong version is
        /// one nobody notices is wrong.
        case noFolderForVersion(String, versionsPath: String)

        public var localizedStringResource: LocalizedStringResource {
            switch self {
            case .nothingReadYet:
                LocalizedStringResource("Read App Store Connect first.", bundle: .here)
            case .everythingIsAlreadyHere:
                LocalizedStringResource("""
                Every language App Store Connect holds is already in this project.
                """, bundle: .here)
            case let .noFolderForVersion(version, versionsPath):
                LocalizedStringResource("""
                App Store Connect is on version \(version), and there is no folder for it. \
                Make \(versionsPath)/\(version) first.
                """, bundle: .here)
            }
        }
    }

    /// What could be taken in, worked out from what the last read found.
    ///
    /// Reads no files and writes none, so a view can ask on every redraw and a
    /// button can be greyed out with the reason on it.
    public static func plan(
        locales: LocaleDrift.Outcome?,
        versions: VersionDrift.Outcome?,
        config: ProjectConfig
    ) -> Result<Plan, Refusal> {
        guard let locales, let versions else { return .failure(.nothingReadYet) }

        if let version = versions.versionToCreate {
            return .failure(.noFolderForVersion(version, versionsPath: config.versionsPath))
        }
        guard locales.missingHere.isEmpty == false else {
            return .failure(.everythingIsAlreadyHere)
        }
        return .success(Plan(locales: locales.missingHere, version: versions.version))
    }

    /// The same, for a caller holding the listing rather than the two outcomes
    /// it worked out. Reads the version folders.
    public static func plan(
        listing: RemoteListing,
        project: Project
    ) throws -> Result<Plan, Refusal> {
        let versions = try VersionDrift.compare(listing: listing, project: project)
        return plan(
            locales: LocaleDrift.compare(listing: listing, config: project.config),
            versions: versions,
            config: project.config
        )
    }

    // MARK: - Writing it

    /// What the adoption did.
    public struct Outcome: Sendable, Equatable {
        /// Languages added to the locale list.
        public var added: [String] = []

        /// Languages that got an app information file written for them.
        public var written: [String] = []

        /// Languages that were already listed and already had a file. Nothing
        /// was written for these.
        public var left: [String] = []

        /// The version the files went into.
        public var version: String

        /// The configuration as it now reads on disk.
        public var config: ProjectConfig
    }

    /// Writes what the plan says.
    ///
    /// Each language is added to the locale list, gets an app information file
    /// written from what App Store Connect holds, and gets the folders its
    /// screenshots go in. That is what puts it in the sidebar: the sidebar
    /// reads the locale list, and the validator wants a file for every name in
    /// it.
    ///
    /// Writes over nothing. A language already listed keeps its place, and an
    /// app information file already there is left exactly as it is, because
    /// what is on disk may be a translation somebody is still working on.
    @discardableResult
    public static func adopt(
        _ plan: Plan,
        listing: RemoteListing,
        in project: Project
    ) throws -> Outcome {
        var config = project.config
        var outcome = Outcome(version: plan.version, config: config)

        for locale in plan.locales.sorted() {
            var touched = false

            if config.locales.contains(locale) == false {
                config.locales.append(locale)
                outcome.added.append(locale)
                touched = true
            }

            let url = project.informationURL(version: plan.version, locale: locale)
            if FileManager.default.fileExists(atPath: url.path) == false {
                let information = SnapshotWriter.makeInformation(locale: locale, listing: listing)
                try ContentWriter.writeAppInformation(information, version: plan.version, in: project)
                outcome.written.append(locale)
                touched = true
            }

            try makeScreenshotFolders(for: locale, plan: plan, config: config, in: project)
            if touched == false { outcome.left.append(locale) }
        }

        guard outcome.added.isEmpty == false else { return outcome }

        // Appended rather than sorted in. The order of the list is the order of
        // the sidebar, and re-sorting would move the source language out of
        // first place on somebody who put it there.
        try project.write(config)
        outcome.config = config
        return outcome
    }

    /// Works out what can be taken in and writes it, for a caller that has the
    /// listing and wants the whole thing done.
    @discardableResult
    public static func adopt(
        listing: RemoteListing,
        in project: Project
    ) throws -> Outcome {
        try adopt(plan(listing: listing, project: project).get(), listing: listing, in: project)
    }

    /// The folders one language's screenshots go in, one per device class the
    /// project ships.
    ///
    /// Made empty, so somebody can drop a screenshot into the right place in
    /// the Finder without building the path by hand. Git keeps no empty folder,
    /// so these last until the next clone and no longer. That is the whole life
    /// they are for.
    private static func makeScreenshotFolders(
        for locale: String,
        plan: Plan,
        config: ProjectConfig,
        in project: Project
    ) throws {
        for deviceClass in config.resolvedDeviceClasses {
            try FileManager.default.createDirectory(
                at: project.screenshotsURL(
                    version: plan.version,
                    locale: locale,
                    deviceClassID: deviceClass.id
                ),
                withIntermediateDirectories: true
            )
        }
    }
}

extension LocaleAdoption.Refusal: CustomStringConvertible {
    public var description: String { String(localized: localizedStringResource) }
}
