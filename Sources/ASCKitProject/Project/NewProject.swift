import Foundation

/// What a new project in a folder would be, read out of the Xcode project
/// beside it.
///
/// The app and the command line tool both start here, so both read the same
/// app, the same languages and the same destination out of the same folder.
/// What they do about a language Xcode gives more than one App Store answer for
/// is theirs: the app asks, and the command line tool leaves it out and names
/// it.
public struct NewProject: Sendable {
    /// The folder holding the Xcode project.
    public let folderURL: URL

    /// The name of the `.xcodeproj`, so a person can see which one was read.
    public let projectName: String

    public let app: XcodeProject.App

    /// Every language Xcode builds the app in, with what the App Store calls
    /// it, in the order Xcode lists them.
    public let regions: [(region: String, outcome: RegionMatch.Outcome)]

    /// Where the listing would go: `.asckit` beside the Xcode project, or the
    /// folder an older project is already in. With a registry, the folder the
    /// registry names, or a new one in its root.
    public let destination: URL

    /// Whether there is a project at the destination already. Writing over one
    /// would take its key identifiers with it, so both front ends stop on this
    /// and each says what it can do about it.
    public let alreadyAProject: Bool

    /// The languages Xcode gives one App Store answer for.
    public var settledLocales: [String] { regions.compactMap(\.outcome.resolved) }

    /// The languages Xcode gives more than one App Store answer for. Nothing
    /// here picks between them, because a listing written in the wrong English
    /// is one nobody notices is wrong.
    public var undecidedRegions: [(region: String, choices: [String])] {
        regions.compactMap { entry in
            if case let .several(codes) = entry.outcome { (entry.region, codes) } else { nil }
        }
    }

    /// The languages a new project would ship, in the order Xcode lists them.
    ///
    /// `chosen` answers the regions Xcode gives more than one App Store locale
    /// for, by region. A region with no answer, and one the App Store has no
    /// locale for, is left out.
    ///
    /// The order is the point. The listing is written in the first language,
    /// and the first region is the one Xcode builds the app in. Putting the
    /// settled languages first instead writes a German listing for an app
    /// written in English, because `de` settles and `en` waits to be chosen.
    public func locales(choosing chosen: [String: String] = [:]) -> [String] {
        var seen: Set<String> = []
        return regions
            .compactMap { entry in
                switch entry.outcome {
                case let .one(code): code
                case .several: chosen[entry.region]
                case .none: nil
                }
            }
            .filter { $0.isEmpty == false && seen.insert($0).inserted }
    }

    /// The language a new project would be written in, which is the language
    /// Xcode builds the app in.
    ///
    /// Named rather than read off the front of `locales(choosing:)`, so a
    /// caller never has to know that the front of that list means anything.
    /// Nil when nothing in the project gives an App Store locale.
    public func sourceLocale(choosing chosen: [String: String] = [:]) -> String? {
        locales(choosing: chosen).first
    }

    /// Reads a folder and works out what a new project in it would be.
    ///
    /// Writes nothing. Refuses a folder with no single Xcode project, the same
    /// as opening one does.
    public static func read(in folderURL: URL, target: String? = nil) throws -> NewProject {
        guard let projectURL = XcodeProject.find(in: folderURL) else {
            throw ProjectError.noXcodeProject(at: folderURL)
        }

        let xcode = try XcodeProject.read(at: projectURL)
        let destination = Project.projectFolder(under: folderURL)

        return try NewProject(
            folderURL: folderURL,
            projectName: projectURL.lastPathComponent,
            app: choose(from: xcode.apps, target: target, in: projectURL.lastPathComponent),
            regions: RegionMatch.outcomes(for: xcode.knownRegions),
            destination: destination,
            alreadyAProject: Project.alreadyAProject(in: folderURL)
        )
    }

    /// Reads a folder the same way, with the project kept outside the
    /// repository.
    ///
    /// The destination is the folder the registry or the repository already
    /// has for this app. A new project goes in a folder of the registry's root,
    /// named after the app.
    public static func read(
        in folderURL: URL,
        target: String? = nil,
        locations: ProjectLocations
    ) throws -> NewProject {
        let found = try read(in: folderURL, target: target)

        guard let resolution = locations.resolve(repo: folderURL) else {
            let name = locations.folderName(
                forDisplayName: found.app.displayName,
                bundleID: found.app.bundleID ?? found.app.displayName
            )
            return NewProject(
                folderURL: found.folderURL,
                projectName: found.projectName,
                app: found.app,
                regions: found.regions,
                destination: locations.root.appending(path: name),
                alreadyAProject: false
            )
        }

        return NewProject(
            folderURL: found.folderURL,
            projectName: found.projectName,
            app: found.app,
            regions: found.regions,
            destination: resolution.dataURL,
            alreadyAProject: FileManager.default.fileExists(
                atPath: resolution.dataURL.appending(path: Project.defaultConfigName).path
            )
        )
    }

    /// The one app the listing is for.
    ///
    /// A project building more than one app is refused rather than guessed at.
    /// Scaffolding for the wrong target writes a listing that pushes to another
    /// app's page.
    private static func choose(
        from apps: [XcodeProject.App],
        target: String?,
        in projectName: String
    ) throws -> XcodeProject.App {
        guard let target else {
            guard let first = apps.first else {
                throw NewProjectError.noApp(in: projectName)
            }
            guard apps.count == 1 else {
                throw NewProjectError.severalApps(apps.map(\.targetName))
            }
            return first
        }

        guard let chosen = apps.first(where: { $0.targetName == target }) else {
            throw NewProjectError.noSuchTarget(target, available: apps.map(\.targetName))
        }
        return chosen
    }
}

public enum NewProjectError: Error, CustomLocalizedStringResourceConvertible {
    case noApp(in: String)
    case severalApps([String])
    case noSuchTarget(String, available: [String])

    public var localizedStringResource: LocalizedStringResource {
        switch self {
        case let .noApp(projectName):
            LocalizedStringResource("\(projectName) builds nothing the App Store lists.", bundle: .here)
        case let .severalApps(names):
            LocalizedStringResource("""
            This Xcode project builds more than one app: \(names.joined(separator: ", ")). \
            ASCKit has to be told which one the listing is for.
            """, bundle: .here)
        case let .noSuchTarget(name, available):
            LocalizedStringResource("""
            There is no app target called \(name). There is: \(available.joined(separator: ", ")).
            """, bundle: .here)
        }
    }
}

extension NewProjectError: CustomStringConvertible {
    public var description: String { String(localized: localizedStringResource) }
}
