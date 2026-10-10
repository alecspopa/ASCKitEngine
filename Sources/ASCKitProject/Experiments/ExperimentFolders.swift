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

    public static func folderName(for name: String) -> String {
        FolderNaming.folderName(for: name)
    }

    public static func folderNames(for items: [(id: String, name: String)]) -> [String: String] {
        FolderNaming.folderNames(for: items)
    }

    /// The folder name of each test, keyed by its id.
    ///
    /// The editable tests are named first, so a locked test with the same name
    /// never takes the folder that holds an editable test's images.
    public static func folderNames(for remote: RemoteExperiments) -> [String: String] {
        let editable = FolderNaming.folderNames(
            for: remote.experiments.filter(\.isEditable).map { ($0.id, $0.name) }
        )
        let locked = FolderNaming.folderNames(
            for: remote.experiments.filter { $0.isEditable == false }.map { ($0.id, $0.name) },
            taken: Set(editable.values)
        )
        return editable.merging(locked) { first, _ in first }
    }

    /// Makes the empty folders a person drops images into, for every language
    /// of every treatment of every editable test.
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
        let experimentNames = folderNames(for: remote)

        for experiment in remote.experiments where experiment.isEditable {
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

    /// Sets somebody emptied on purpose, as `ScreenshotFolder.emptied` says.
    public let emptied: Set<ExperimentSlot>

    /// The key of `creative` for one treatment.
    public static func creativeKey(experiment: String, treatment: String) -> String {
        "\(experiment)/\(treatment)"
    }

    public init(
        screenshots: [ExperimentSlot: [ScreenshotFile]] = [:],
        previews: [ExperimentSlot: [PreviewFile]] = [:],
        creative: [String: CreativeFolder] = [:],
        emptied: Set<ExperimentSlot> = []
    ) {
        self.screenshots = screenshots
        self.previews = previews
        self.creative = creative
        self.emptied = emptied
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
        var emptied: Set<ExperimentSlot> = []

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

                let place = LibraryContentPlace.treatment(
                    experiment: experiment.lastPathComponent, treatment: treatment.lastPathComponent
                )
                let sets = ScreenshotFolder.load(from: treatment, skipping: place.reservedFolderNames)
                let slot = { (set: ScreenshotSlot) in
                    ExperimentSlot(
                        experiment: experiment.lastPathComponent,
                        treatment: treatment.lastPathComponent,
                        locale: set.locale,
                        deviceClassID: set.deviceClassID
                    )
                }
                for (set, files) in sets.screenshots {
                    screenshots[slot(set)] = files
                }
                emptied.formUnion(sets.emptied.map(slot))
            }
        }
        return ExperimentContent(screenshots: screenshots, previews: previews, creative: creative, emptied: emptied)
    }
}
