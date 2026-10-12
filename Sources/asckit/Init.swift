import ArgumentParser
import ASCKitAPI
import ASCKitProject
import Foundation

/// Makes a project folder beside an `.xcodeproj`, filled in from what the
/// Xcode project already says about the app.
struct Init: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "init",
        abstract: "Make a project folder for an Xcode project.",
        discussion: """
        Reads the `.xcodeproj` in the folder for the app's name, its bundle identifier, \
        the version being worked on and the languages it ships, and writes the project \
        to ~/Documents/ASCKit/<app name>. ~/Documents/ASCKit/locations.json records which \
        repository it belongs to. Pass --data to put it in another folder.

        A new project is never written into the repository.

        Refuses rather than write over a project that is already there. `--force` starts \
        again and says what was in the old project. A project in the data folder is \
        rebuilt there, and its old files go to the Trash. A project in the repository, \
        such as an \(ProjectScaffold.folderName) folder, is replaced by a new project \
        in the data folder, and the old folder goes to the Trash.

        The listing is written in one language and translated into the rest. That one is \
        the language Xcode builds the app in. Pass --source-locale when the App Store has \
        more than one answer for it, such as the four Englishes for `en`.

        Any other language Xcode gives more than one answer for is left out and named. \
        Pass it with --locale, or add it later.
        """
    )

    @Argument(help: ArgumentHelp(
        "The folder holding the Xcode project. Defaults to the current one.",
        valueName: "folder"
    ))
    var folder: String = "."

    @Option(name: .long, help: ArgumentHelp(
        "Which app target, when the project builds more than one.",
        valueName: "name"
    ))
    var target: String?

    @Option(name: .long, help: ArgumentHelp(
        "The language the listing is written in. Defaults to the one Xcode builds the app in.",
        valueName: "code"
    ))
    var sourceLocale: String?

    @Option(name: .long, help: ArgumentHelp(
        "Another language to ship, repeated. Overrides what Xcode says.",
        valueName: "code"
    ))
    var locale: [String] = []

    @Option(name: .long, help: ArgumentHelp(
        "Which platform's version to write, for an app that sells on more than one.",
        valueName: "name"
    ))
    var platform: String?

    @Option(name: .long, help: ArgumentHelp("Which version to start at.", valueName: "version"))
    var appVersion: String?

    @Option(name: .long, help: ArgumentHelp("The App Store Connect Key ID.", valueName: "id"))
    var keyID: String?

    @Option(name: .long, help: ArgumentHelp(
        "The Issuer ID. Leave out for an individual key.",
        valueName: "id"
    ))
    var issuerID: String?

    @Option(name: .long, help: ArgumentHelp(
        "A screenshot size to ship, repeated. Defaults to the largest one the platform takes.",
        valueName: "id"
    ))
    var deviceClass: [String] = []

    @Option(name: .long, help: ArgumentHelp(
        "The folder to write the project to. Defaults to ~/Documents/ASCKit/<app name>.",
        valueName: "path"
    ))
    var data: String?

    @Flag(name: .long, help: "Start again. The old project goes to the Trash.")
    var force = false

    func run() throws {
        let currentFolder = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        let folderURL = URL(fileURLWithPath: folder, relativeTo: currentFolder).standardizedFileURL

        let locations = try ProjectLocations.load(
            root: ProjectLocations.defaultRoot(home: FileManager.default.homeDirectoryForCurrentUser)
        )
        let found = try NewProject.read(in: folderURL, target: target, locations: locations)
        let destination = data.map { URL(fileURLWithPath: $0, relativeTo: currentFolder).standardizedFileURL }
            ?? found.destination
        let languages = try chooseLanguages(in: found)
        let bundleID = try require(found.app.bundleID, "bundle identifier", flag: nil)
        let key = try require(keyID, "Key ID", flag: "--key-id")
        let platformID = try mapped { () throws(NewProject.ChoiceError) in
            try NewProject.platformID(named: platform)
        }
        let deviceClasses = try mapped { () throws(NewProject.ChoiceError) in
            try NewProject.deviceClassIDs(deviceClass, platform: platformID)
        }

        let config = ProjectConfig(
            bundleID: bundleID,
            keyID: key,
            issuerID: issuerID,
            sourceLocale: languages.source,
            locales: languages.all,
            deviceClasses: deviceClasses,
            platform: platformID
        )
        let version = appVersion ?? found.app.marketingVersion ?? "1.0"

        print("\(found.app.displayName) (\(config.bundleID)), version \(version)")
        print("Screenshot sizes: \(config.deviceClasses.joined(separator: ", "))")
        print("Languages: \(languages.all.joined(separator: ", "))")
        print("Written in: \(languages.source)")
        if let platform = config.platform {
            print("Platform: \(platform)")
        }

        try write(config: config, version: version, to: destination, repo: folderURL, locations: locations)
    }

    // MARK: - Languages

    /// `--source-locale` says which language the listing is written in, and
    /// `--locale` says what else to ship. The choosing is in `NewProject`.
    private func chooseLanguages(in found: NewProject) throws -> NewProject.Languages {
        let languages = try mapped { () throws(NewProject.ChoiceError) in
            try found.languages(source: sourceLocale, locales: locale)
        }
        sayWhatIsLeftOut(of: languages.all, in: found)
        return languages
    }

    /// Runs a choice and turns its refusal into the words of this command,
    /// which name the flags that answer it.
    private func mapped<T>(_ choice: () throws(NewProject.ChoiceError) -> T) throws -> T {
        do {
            return try choice()
        } catch {
            switch error {
            case let .unknownLocale(code, suggestion):
                throw InitError.unknownLocale(code, suggestion: suggestion)
            case .noLanguagesInXcode:
                throw InitError.noLanguagesInXcode
            case let .sourceNeedsAChoice(region, choices):
                throw InitError.sourceLanguageNeedsAChoice(region, choices: choices)
            case let .sourceNotOnTheAppStore(region):
                throw InitError.sourceLanguageNotOnTheAppStore(region)
            case let .unknownDeviceClass(id):
                throw InitError.unknownDeviceClass(id)
            case let .unknownPlatform(name):
                throw InitError.unknownPlatform(name)
            }
        }
    }

    /// Names every language Xcode builds the app in that the listing will not
    /// have. The person reading this output is the only check on a language
    /// going missing quietly.
    private func sayWhatIsLeftOut(of codes: [String], in found: NewProject) {
        for (region, outcome) in found.regionsLeftOut(of: codes) {
            switch outcome {
            case let .one(code):
                print("The app is built in \(region), and the listing will not have \(code).")
            case let .several(choices):
                print("\(region) could be \(choices.joined(separator: ", ")). "
                    + "Left out. Pass --locale to say which.")
            case .none:
                print("\(region) is not a language the App Store lists. Left out.")
            }
        }
    }

    // MARK: - Writing

    private func write(
        config: ProjectConfig,
        version: String,
        to destination: URL,
        repo folderURL: URL,
        locations: ProjectLocations
    ) throws {
        var locations = locations

        switch NewProject.placement(destination: destination, repo: folderURL) {
        case let .rebuild(plan):
            // A project in the folder the registry names is rebuilt where it is.
            guard force else {
                throw InitError.alreadyAProject(at: destination, plan: plan)
            }

            // Said before it happens, even with --force, because the person
            // reading this output is the only record of what was there.
            describe(plan)
            let trashed = try ProjectRebuild.rebuild(plan, config: config, version: version)
            print("Moved \(countedNoun(trashed.count, "item")) to the Trash.")
            print("Wrote \(plan.folderURL.path).")
        case let .replaceLegacy(plan):
            guard force else {
                throw InitError.alreadyAProject(at: plan.folderURL, plan: plan)
            }
            guard FileManager.default.fileExists(atPath: destination.path) == false else {
                throw InitError.destinationTaken(destination)
            }

            describe(plan)
            try locations.replaceLegacy(
                plan, config: config, version: version,
                to: destination, repo: folderURL
            )
            print("Wrote \(destination.path).")
            print("Moved \(plan.folderURL.path) to the Trash.")
            return
        case .create:
            try ProjectScaffold.create(at: destination, config: config, version: version)
            print("Wrote \(destination.path).")
        }

        locations.register(bundleID: config.bundleID, data: destination, repo: folderURL)
        try locations.save()
    }

    private func describe(_ plan: ProjectRebuild.Plan) {
        guard plan.isEmpty == false else { return }
        print("Removing from \(plan.folderURL.path):")
        if plan.languages.isEmpty == false {
            print("  \(plan.languages.count) language(s) of listing text: "
                + plan.languages.joined(separator: ", "))
        }
        if plan.screenshotCount > 0 {
            print("  \(plan.screenshotCount) screenshot(s)")
        }
        if plan.versions.isEmpty == false {
            print("  version(s): \(plan.versions.joined(separator: ", "))")
        }
        if plan.hasHistory {
            print("  the record of what was pushed before")
        }
        if let keyID = plan.keyID {
            print("  the configuration, including the Key ID \(keyID)")
        }
    }

    private func require(_ value: String?, _ what: String, flag: String?) throws -> String {
        guard let value, value.isEmpty == false else {
            throw InitError.missing(what, flag: flag)
        }
        return value
    }
}

enum InitError: Error, CustomStringConvertible {
    case unknownLocale(String, suggestion: String?)
    case unknownDeviceClass(String)
    case unknownPlatform(String)
    case sourceLanguageNeedsAChoice(String, choices: [String])
    case sourceLanguageNotOnTheAppStore(String)
    case noLanguagesInXcode
    case missing(String, flag: String?)
    case alreadyAProject(at: URL, plan: ProjectRebuild.Plan)
    case destinationTaken(URL)

    var description: String {
        switch self {
        case let .destinationTaken(folder):
            "There is already a folder at \(folder.path). Pass --data to write the project to another folder."
        case let .unknownDeviceClass(id):
            "\(id) is not a screenshot size ASCKit knows. There is: "
                + DeviceClass.all.map(\.id).joined(separator: ", ") + "."
        case let .unknownPlatform(name):
            "\(name) is not a platform ASCKit knows. There is: "
                + Platform.all.map(\.id).joined(separator: ", ") + "."
        case let .unknownLocale(code, suggestion):
            "\(code) is not a locale App Store Connect accepts."
                + (suggestion.map { " Did you mean \($0)?" } ?? "")
        case let .sourceLanguageNeedsAChoice(region, choices):
            "The app is written in \(region), and the App Store has "
                + choices.joined(separator: ", ") + ". "
                + "Pass --source-locale to say which one the listing is written in."
        case let .sourceLanguageNotOnTheAppStore(region):
            "The app is written in \(region), and the App Store has no language for it. "
                + "Pass --source-locale to say which language the listing is written in."
        case .noLanguagesInXcode:
            "The Xcode project lists no languages. "
                + "Pass --source-locale to say which language the listing is written in."
        case let .missing(what, flag):
            "This needs the \(what)." + (flag.map { " Pass it with \($0)." } ?? "")
        case let .alreadyAProject(folder, plan):
            "There is already a project at \(folder.path)"
                + (plan.languages.isEmpty ? "" : ", holding \(plan.languages.joined(separator: ", "))")
                + (plan.screenshotCount > 0 ? " and \(plan.screenshotCount) screenshots" : "")
                + ". Use --force to start again. The new project goes to the data folder, "
                + "and the old one goes to the Trash."
        }
    }
}
