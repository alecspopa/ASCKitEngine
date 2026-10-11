import ASCKitAPI
import Foundation

/// The choices that turn what Xcode says, and what a person passed, into a
/// project configuration.
///
/// Nothing here prints or prompts. A front end maps `ChoiceError` to its own
/// words, because only it knows how a person passes a flag.
public extension NewProject {
    /// The languages to ship, and which of them the listing is written in.
    ///
    /// Two answers rather than one list, because the source language is a
    /// thing a person names. Reading it off the front of a list means a flag
    /// typed in another order writes a German listing for an English app.
    struct Languages: Sendable {
        public let source: String
        public let all: [String]
    }

    enum ChoiceError: Error, Sendable {
        case unknownLocale(String, suggestion: String?)
        case noLanguagesInXcode
        case sourceNeedsAChoice(region: String, choices: [String])
        case sourceNotOnTheAppStore(region: String)
        case unknownDeviceClass(String)
        case unknownPlatform(String)
    }

    /// What Xcode says, turned into App Store codes, with the choices of the
    /// person on top.
    ///
    /// `source` says which language the listing is written in, and `locales`
    /// says what else to ship. Xcode answers whichever of the two nobody gave.
    /// A region the App Store answers twice for, such as `en`, stops this when
    /// it is the source: a listing written in the wrong English is one nobody
    /// notices is wrong.
    func languages(source: String?, locales: [String]) throws(ChoiceError) -> Languages {
        for code in [source].compactMap(\.self) + locales where StoreLocale.isKnown(code) == false {
            throw .unknownLocale(code, suggestion: StoreLocale.suggestion(for: code))
        }

        let written = try sourceLanguage(named: source)
        var seen: Set<String> = []
        let all = ([written] + (locales.isEmpty ? self.locales() : locales))
            .filter { seen.insert($0).inserted }
        return Languages(source: written, all: all)
    }

    /// The regions Xcode builds the app in that the listing will not have,
    /// given the languages it will have.
    func regionsLeftOut(of codes: [String]) -> [(region: String, outcome: RegionMatch.Outcome)] {
        regions.filter { $0.outcome.choices.contains(where: codes.contains) == false }
    }

    /// Which platform's version a project writes.
    ///
    /// Nil for an app on one platform, which is most apps. App Store Connect
    /// then answers with whichever version the app has.
    static func platformID(named name: String?) throws(ChoiceError) -> String? {
        guard let name else { return nil }
        guard let known = Platform.named(name) else { throw .unknownPlatform(name) }
        return known.id
    }

    /// The screenshot sizes to ship.
    ///
    /// Xcode says nothing about them, so they are asked for rather than read,
    /// and refused when they are not ones ASCKit knows. With none asked for,
    /// the largest one the platform takes.
    static func deviceClassIDs(
        _ ids: [String],
        platform: String?
    ) throws(ChoiceError) -> [String] {
        guard ids.isEmpty == false else {
            let platform = platform.flatMap(Platform.named) ?? .ios
            return DeviceClass.first(on: platform).map { [$0.id] } ?? []
        }

        for id in ids where DeviceClass.named(id) == nil {
            throw .unknownDeviceClass(id)
        }
        return ids
    }

    // MARK: - Where the project goes

    /// What writing a project to a destination has to do about what is there.
    enum Placement: Sendable {
        /// A project is at the destination, and is rebuilt where it is.
        case rebuild(ProjectRebuild.Plan)

        /// A project is in the repository, and moves to the destination.
        case replaceLegacy(ProjectRebuild.Plan)

        /// Nothing is there.
        case create
    }

    static func placement(destination: URL, repo: URL) -> Placement {
        let configPath = destination.appending(path: Project.defaultConfigName).path

        if FileManager.default.fileExists(atPath: configPath) {
            return .rebuild(ProjectRebuild.plan(at: destination))
        }
        if Project.alreadyAProject(in: repo) {
            return .replaceLegacy(ProjectRebuild.plan(at: repo))
        }
        return .create
    }

    /// Moves a project kept in the repository to the destination.
    ///
    /// The new folder and the registry come first and the Trash last, so a
    /// failure never leaves the person with no project.
    static func replaceLegacy(
        _ plan: ProjectRebuild.Plan,
        config: ProjectConfig,
        version: String,
        to destination: URL,
        repo: URL,
        locations: inout ProjectLocations
    ) throws {
        try ProjectScaffold.create(at: destination, config: config, version: version)
        locations.register(bundleID: config.bundleID, data: destination, repo: repo)
        try locations.save()
        try FileManager.default.trashItem(at: plan.folderURL, resultingItemURL: nil)
    }

    // MARK: - The language the listing is written in

    private func sourceLanguage(named source: String?) throws(ChoiceError) -> String {
        if let source { return source }

        guard let development = regions.first else { throw .noLanguagesInXcode }

        switch development.outcome {
        case let .one(code):
            return code
        case let .several(codes):
            throw .sourceNeedsAChoice(region: development.region, choices: codes)
        case .none:
            throw .sourceNotOnTheAppStore(region: development.region)
        }
    }
}
