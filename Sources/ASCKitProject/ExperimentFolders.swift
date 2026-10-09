import ASCKitAPI
import Foundation

/// Where the images of a Product Page Optimization test live.
///
///     product-page-optimization/
///     └── Bigger buttons/          the test, named as App Store Connect names it
///         └── Treatment A/         a treatment of that test
///             └── en-US/
///                 └── iphone-6.9/
///                     └── 01-running-low-iPhone-6.9-en_US.png
///
/// Beside `versions`, not inside one. A test belongs to the app and can run
/// across two releases, so a copy in each version folder would let two folders
/// disagree about one test.
///
/// ASCKit never makes a test, a treatment or a language of a treatment on App
/// Store Connect. They are made there, and a folder here only holds the images
/// that go into them.
public enum ExperimentFolders {
    public static let folderName = "product-page-optimization"

    /// A name from App Store Connect as a folder name.
    ///
    /// The name stays readable. Only what a file system refuses, or what would
    /// read as a path, is replaced.
    public static func folderName(for name: String) -> String {
        let cleaned = name
            .map { "/:\\".contains($0) || $0.isNewline ? "-" : $0 }
            .map(String.init)
            .joined()
            .trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: ".")))
        return cleaned.isEmpty ? "untitled" : cleaned
    }

    /// The folder name of each item, keyed by its id.
    ///
    /// Two items can share a name, and one folder must not hold both. The
    /// second in id order gets the end of its id, so the same two items are
    /// named the same way on every read.
    public static func folderNames(for items: [(id: String, name: String)]) -> [String: String] {
        var result: [String: String] = [:]
        var taken: Set<String> = []
        for item in items.sorted(by: { $0.id < $1.id }) {
            var candidate = folderName(for: item.name)
            if taken.contains(candidate.lowercased()) {
                candidate += " (\(item.id.suffix(4)))"
            }
            taken.insert(candidate.lowercased())
            result[item.id] = candidate
        }
        return result
    }

    /// Makes the empty folders a person drops images into, for every language
    /// of every treatment of every draft test.
    ///
    /// Only the device classes of the platform the test is for. Returns the
    /// folders it made.
    @discardableResult
    public static func scaffold(
        _ remote: RemoteExperiments,
        in project: Project
    ) throws -> [URL] {
        var made: [URL] = []
        let deviceClasses = project.config.resolvedDeviceClasses
        let experimentNames = folderNames(for: remote.experiments.map { ($0.id, $0.name) })

        for experiment in remote.experiments {
            let treatmentNames = folderNames(for: experiment.treatments.map { ($0.id, $0.name) })
            let fitting = deviceClasses.filter { experiment.platform == nil || $0.platform == experiment.platform }

            for treatment in experiment.treatments {
                for localization in treatment.localizations {
                    for deviceClass in fitting {
                        let url = project.experimentURL(
                            experiment: experimentNames[experiment.id] ?? experiment.name,
                            treatment: treatmentNames[treatment.id] ?? treatment.name,
                            locale: localization.locale,
                            deviceClassID: deviceClass.id
                        )
                        guard FileManager.default.fileExists(atPath: url.path) == false else { continue }
                        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                        made.append(url)
                    }
                }
            }
        }
        return made
    }
}

public extension Project {
    var experimentsURL: URL { rootURL.appending(path: ExperimentFolders.folderName) }

    func experimentURL(experiment: String, treatment: String) -> URL {
        experimentsURL.appending(path: experiment).appending(path: treatment)
    }

    func experimentURL(
        experiment: String,
        treatment: String,
        locale: String,
        deviceClassID: String
    ) -> URL {
        experimentURL(experiment: experiment, treatment: treatment)
            .appending(path: locale)
            .appending(path: deviceClassID)
    }
}

// MARK: - On disk

/// One folder of images, named by the test, the treatment, the language and
/// the device class.
public struct ExperimentSlot: Sendable, Hashable {
    /// Folder names, not ids. A folder is what a person sees.
    public let experiment: String
    public let treatment: String
    public let locale: String
    public let deviceClassID: String

    public init(experiment: String, treatment: String, locale: String, deviceClassID: String) {
        self.experiment = experiment
        self.treatment = treatment
        self.locale = locale
        self.deviceClassID = deviceClassID
    }

    /// The key of `ExperimentContent.creative`.
    public var treatmentKey: String {
        ExperimentContent.creativeKey(experiment: experiment, treatment: treatment)
    }

    /// The folder of this slot, below the experiments folder.
    public var path: String { "\(treatmentKey)/\(locale)/\(deviceClassID)" }
}

/// Everything the `product-page-optimization` folder holds, read and not yet
/// checked.
public struct ExperimentContent: Sendable {
    public let screenshots: [ExperimentSlot: [ScreenshotFile]]

    /// From `<test>/<treatment>/previews/<locale>/<device class>/`.
    public let previews: [ExperimentSlot: [PreviewFile]]

    /// From `<test>/<treatment>/creative/<locale>/`, by `<test>/<treatment>`.
    public let creative: [String: CreativeFolder]

    /// The key of `creative` for one treatment.
    public static func creativeKey(experiment: String, treatment: String) -> String {
        "\(experiment)/\(treatment)"
    }

    public init(
        screenshots: [ExperimentSlot: [ScreenshotFile]] = [:],
        previews: [ExperimentSlot: [PreviewFile]] = [:],
        creative: [String: CreativeFolder] = [:]
    ) {
        self.screenshots = screenshots
        self.previews = previews
        self.creative = creative
    }

    public func screenshots(in slot: ExperimentSlot) -> [ScreenshotFile] {
        screenshots[slot] ?? []
    }

    public func previews(in slot: ExperimentSlot) -> [PreviewFile] {
        previews[slot] ?? []
    }

    /// The test folders found, whatever App Store Connect holds.
    public var experimentFolders: Set<String> { Set(screenshots.keys.map(\.experiment)) }

    /// The treatment folders found under one test folder.
    public func treatmentFolders(experiment: String) -> Set<String> {
        Set(screenshots.keys.filter { $0.experiment == experiment }.map(\.treatment))
    }

    public var isEmpty: Bool { screenshots.values.allSatisfy(\.isEmpty) }
}

public enum ExperimentContentStore {
    public static let previewsFolderName = Project.previewsFolderName

    public static func load(in project: Project) -> ExperimentContent {
        var screenshots: [ExperimentSlot: [ScreenshotFile]] = [:]
        var previews: [ExperimentSlot: [PreviewFile]] = [:]
        var creative: [String: CreativeFolder] = [:]

        for experiment in DirectoryListing.directories(in: project.experimentsURL) {
            for treatment in DirectoryListing.directories(in: experiment) {
                let folder = PreviewFolder.load(from: treatment.appending(path: previewsFolderName))
                for (slot, files) in folder.previews {
                    previews[ExperimentSlot(
                        experiment: experiment.lastPathComponent,
                        treatment: treatment.lastPathComponent,
                        locale: slot.locale,
                        deviceClassID: slot.deviceClassID
                    )] = files
                }

                let art = CreativeFolder.load(from: treatment.appending(path: CreativeFolder.folderName))
                if art.isEmpty == false {
                    creative[ExperimentContent.creativeKey(
                        experiment: experiment.lastPathComponent,
                        treatment: treatment.lastPathComponent
                    )] = art
                }

                // No language code is `previews` or `creative`, so the names are free.
                let reserved: Set = [previewsFolderName, CreativeFolder.folderName]
                for locale in DirectoryListing.directories(in: treatment) where reserved.contains(locale.lastPathComponent) == false {
                    for device in DirectoryListing.directories(in: locale) {
                        let slot = ExperimentSlot(
                            experiment: experiment.lastPathComponent,
                            treatment: treatment.lastPathComponent,
                            locale: locale.lastPathComponent,
                            deviceClassID: device.lastPathComponent
                        )
                        screenshots[slot] = DirectoryListing.files(in: device).map(ImageInspector.inspect)
                    }
                }
            }
        }
        return ExperimentContent(screenshots: screenshots, previews: previews, creative: creative)
    }
}
