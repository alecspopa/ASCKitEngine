import ASCKitAPI
import Foundation

/// Turns what App Store Connect holds into the files a project keeps.
///
/// Used to start a project from a listing that already exists, so the first
/// step is not retyping eleven languages out of the web page.
public enum SnapshotWriter {
    public struct Outcome: Sendable {
        public var written: [String] = []
        public var skipped: [String] = []
    }

    /// Builds a app information file from one language of a listing.
    ///
    /// Anything empty on App Store Connect is left out rather than written as
    /// an empty string, because an empty string blanks the field on the next
    /// push while a missing field leaves it alone.
    public static func makeInformation(
        locale: String,
        listing: RemoteListing
    ) -> AppInformation {
        var fields = AppInformation.Fields()
        let values = values(for: locale, in: listing)

        for field in MetadataField.allCases {
            guard let value = values[field.rawValue], value.isEmpty == false else { continue }
            fields[field] = value
        }

        // What is live has by definition been through review, so it is not a
        // draft and not something a machine wrote.
        return AppInformation(
            locale: locale,
            status: .approved,
            fields: fields
        )
    }

    /// Writes one app information file per language of the listing.
    ///
    /// Never overwrites unless asked. A pull that silently replaced local work
    /// would be the worst thing this tool could do.
    @discardableResult
    public static func write(
        listing: RemoteListing,
        to project: Project,
        version: String,
        overwrite: Bool = false
    ) throws -> Outcome {
        var outcome = Outcome()
        for locale in listing.locales.sorted() {
            let url = project.informationURL(version: version, locale: locale)
            if FileManager.default.fileExists(atPath: url.path), overwrite == false {
                outcome.skipped.append(locale)
                continue
            }

            let copy = makeInformation(locale: locale, listing: listing)
            try ContentWriter.writeAppInformation(copy, version: version, in: project)
            outcome.written.append(locale)
        }
        return outcome
    }

    // MARK: - Filling what is empty here

    /// One language's file as it reads once the empty fields are filled, and
    /// the fields that were filled.
    public struct Filled: Sendable, Equatable {
        public var information: AppInformation

        /// Empty when the file already said something in every field App Store
        /// Connect holds. Nothing was changed in that case.
        public var fields: [MetadataField]
    }

    /// What filling a whole version folder did, keyed by language.
    public struct FillOutcome: Sendable, Equatable {
        public var filled: [String: [MetadataField]] = [:]

        public var isEmpty: Bool { filled.isEmpty }

        /// The languages that got something, sorted.
        public var locales: [String] { filled.keys.sorted() }
    }

    /// Puts what App Store Connect holds into the fields this language leaves
    /// empty, and leaves every other field exactly as it is.
    ///
    /// A field is empty when the file has no value for it, or a value that is
    /// nothing but spaces. Words somebody wrote are never touched, so this is
    /// safe to run against a translation in progress.
    ///
    /// The status stays as the file says. What comes down is already live, so
    /// it needs no approval, and a draft that a person is still writing must
    /// not become publishable because one field arrived from the store.
    public static func fill(_ information: AppInformation, from listing: RemoteListing) -> Filled {
        let values = values(for: information.locale, in: listing)
        var filled = information
        var fields: [MetadataField] = []

        for field in MetadataField.allCases {
            guard isEmpty(information.fields[field]) else { continue }
            guard let value = values[field.rawValue], value.isEmpty == false else { continue }

            filled.fields[field] = value
            fields.append(field)
        }
        return Filled(information: filled, fields: fields)
    }

    /// The same for every language of a version folder, writing each file that
    /// gained something.
    ///
    /// A language with no file is left alone. Making one is what
    /// `LocaleAdoption` is for, and it asks first.
    @discardableResult
    public static func fill(
        _ information: [String: AppInformation],
        from listing: RemoteListing,
        version: String,
        in project: Project
    ) throws -> FillOutcome {
        var outcome = FillOutcome()

        for locale in information.keys.sorted() {
            guard let onDisk = information[locale] else { continue }

            let filled = fill(onDisk, from: listing)
            guard filled.fields.isEmpty == false else { continue }

            try ContentWriter.writeAppInformation(filled.information, version: version, in: project)
            outcome.filled[locale] = filled.fields
        }
        return outcome
    }

    /// Rewrites the configuration's locale list to what App Store Connect
    /// actually holds, which is the only authoritative answer to what codes it
    /// accepts.
    ///
    /// An ignored language keeps its place. The store has no page for it and
    /// never will, which is the decision rather than a gap, and dropping it
    /// would make the Xcode check ask for that page again on the next run.
    public static func updateLocales(
        in project: Project,
        from listing: RemoteListing
    ) throws -> ProjectConfig {
        var config = project.config
        config.locales = Set(listing.locales).union(config.ignoredLocales).sorted()
        try project.write(config)
        return config
    }

    // MARK: - Shared

    /// One language's values, from both resources at once.
    ///
    /// The app information wins where the two hold the same key, which is the
    /// resource the name and the subtitle actually live on.
    private static func values(for locale: String, in listing: RemoteListing) -> [String: String] {
        (listing.appInfoLocalizations[locale]?.values ?? [:])
            .merging(listing.versionLocalizations[locale]?.values ?? [:]) { first, _ in first }
    }

    /// A field with nothing in it. Spaces count as nothing: a field holding a
    /// space reads as empty on screen and pushes as empty to the store.
    private static func isEmpty(_ value: String?) -> Bool {
        value?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true
    }
}

private extension RemoteListing {
    /// App Store Connect does not say which language is the source, so nothing
    /// here should pretend to know.
    var sourceLocaleGuess: String? { nil }
}
