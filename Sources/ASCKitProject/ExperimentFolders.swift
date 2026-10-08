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
}

/// Everything the `product-page-optimization` folder holds, read and not yet
/// checked.
public struct ExperimentContent: Sendable {
    public let screenshots: [ExperimentSlot: [ScreenshotFile]]

    /// From `<test>/<treatment>/previews/<locale>/<device class>/`.
    public let previews: [ExperimentSlot: [PreviewFile]]

    /// From `<test>/<treatment>/creative/<locale>/`, by `<test>/<treatment>`.
    public let creative: [String: CreativeFolder]

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
    private static let ignoredFileNames: Set<String> = [".DS_Store", "Thumbs.db"]
    public static let previewsFolderName = "previews"

    public static func load(in project: Project) -> ExperimentContent {
        var screenshots: [ExperimentSlot: [ScreenshotFile]] = [:]
        var previews: [ExperimentSlot: [PreviewFile]] = [:]
        var creative: [String: CreativeFolder] = [:]

        for experiment in directories(in: project.experimentsURL) {
            for treatment in directories(in: experiment) {
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
                    creative["\(experiment.lastPathComponent)/\(treatment.lastPathComponent)"] = art
                }

                // No language code is `previews` or `creative`, so the names are free.
                let reserved: Set = [previewsFolderName, CreativeFolder.folderName]
                for locale in directories(in: treatment) where reserved.contains(locale.lastPathComponent) == false {
                    for device in directories(in: locale) {
                        let slot = ExperimentSlot(
                            experiment: experiment.lastPathComponent,
                            treatment: treatment.lastPathComponent,
                            locale: locale.lastPathComponent,
                            deviceClassID: device.lastPathComponent
                        )
                        screenshots[slot] = files(in: device).map(ImageInspector.inspect)
                    }
                }
            }
        }
        return ExperimentContent(screenshots: screenshots, previews: previews, creative: creative)
    }

    private static func entries(in directory: URL) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )) ?? []
    }

    private static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
    }

    private static func directories(in directory: URL) -> [URL] {
        entries(in: directory).filter(isDirectory).sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// A file with the wrong extension is kept on purpose, so the validator
    /// reports it rather than something else uploading it.
    private static func files(in directory: URL) -> [URL] {
        entries(in: directory)
            .filter { isDirectory($0) == false && ignoredFileNames.contains($0.lastPathComponent) == false }
            .sorted { $0.lastPathComponent.compare($1.lastPathComponent, options: .numeric) == .orderedAscending }
    }
}

// MARK: - The plan

/// What a push of the images of the draft tests would do.
///
/// Kept apart from `ChangePlan`. A test belongs to no version, so it has no
/// version state and no version folder, and it is read and pushed without
/// either.
public struct ExperimentPlan: Sendable {
    public struct SetPlan: Sendable, Identifiable {
        public let experimentID: String
        public let experimentName: String
        public let treatmentID: String
        public let treatmentName: String
        public let locale: String
        public let treatmentLocalizationID: String
        public let deviceClass: DeviceClass
        public let localFiles: [ScreenshotFile]

        /// How the slot compares in the App Asset Library.
        public let library: LibrarySlot

        public var id: String { "\(treatmentID)|\(locale)|\(deviceClass.id)" }
        public var action: ChangePlan.ScreenshotPlan.Action { LibraryPlanner.action(for: library) }
        public var changesAnything: Bool { library.isUnchanged == false }
        public var remoteCount: Int { library.current.count }

        /// One line saying where the set is, for a step or a failure.
        public var label: String { "\(experimentName) / \(treatmentName) / \(locale)" }
    }

    /// A folder of images with no place to go.
    public struct Unplaced: Sendable, Hashable, Identifiable {
        public enum Reason: Sendable, Hashable {
            /// No draft test has this name. It is finished, or never existed.
            case noDraftExperiment
            case noTreatment
            /// The treatment has no page for this language on App Store
            /// Connect, and ASCKit never makes one.
            case noLanguage
            case deviceClassNotListed
        }

        public let slot: ExperimentSlot
        public let imageCount: Int
        public let reason: Reason
        public var id: String {
            "\(slot.experiment)|\(slot.treatment)|\(slot.locale)|\(slot.deviceClassID)"
        }
    }

    /// The app previews of one device class in one language of a treatment.
    public struct PreviewSetPlan: Sendable, Identifiable {
        public let experimentName: String
        public let treatmentID: String
        public let treatmentName: String
        public let locale: String
        public let treatmentLocalizationID: String
        public let deviceClass: DeviceClass
        public let localFiles: [PreviewFile]
        public let library: LibrarySlot

        public var id: String { "\(treatmentID)|\(locale)|\(deviceClass.id)|previews" }
        public var changesAnything: Bool { library.isUnchanged == false }
        public var action: ChangePlan.ScreenshotPlan.Action { LibraryPlanner.action(for: library) }
        public var label: String { "\(experimentName) / \(treatmentName) / \(locale)" }
    }

    public let sets: [SetPlan]
    public let unplaced: [Unplaced]

    /// The header or search results art of one language of a treatment.
    public struct CreativeSetPlan: Sendable, Identifiable {
        public let treatmentID: String
        public let label: String
        public let treatmentLocalizationID: String
        public let plan: CreativePlan

        public var id: String { "\(treatmentLocalizationID)|\(plan.role.rawValue)" }
    }

    /// Only through the App Asset Library, so empty without a record.
    public let previewSets: [PreviewSetPlan]
    public let creativeSets: [CreativeSetPlan]

    public init(
        sets: [SetPlan],
        unplaced: [Unplaced],
        previewSets: [PreviewSetPlan] = [],
        creativeSets: [CreativeSetPlan] = []
    ) {
        self.sets = sets
        self.unplaced = unplaced
        self.previewSets = previewSets
        self.creativeSets = creativeSets
    }

    public var changingSets: [SetPlan] { sets.filter(\.changesAnything) }

    /// One line for each preview set and each piece of art that changes in a
    /// treatment, for a terminal. English, because a terminal reads it.
    public func libraryLines(treatmentID: String) -> [String] {
        let previews = previewSets.filter { $0.treatmentID == treatmentID && $0.changesAnything }.map { item in
            "\(item.locale)/\(item.deviceClass.id) previews: \(Self.describe(item.library))"
        }
        let art = creativeSets.filter { $0.treatmentID == treatmentID && $0.plan.changesAnything }.map { item in
            let locale = item.plan.locale
            return switch (item.plan.file, item.plan.usesHeader) {
            case (nil, _): "\(locale) \(item.plan.role.rawValue): take it off"
            case (_?, true): "\(locale) \(item.plan.role.rawValue): show the header"
            case let (file?, false): "\(locale) \(item.plan.role.rawValue): put up \(file.fileName)"
            }
        }
        return previews + art
    }

    static func describe(_ slot: LibrarySlot) -> String {
        if slot.toRemove.isEmpty, slot.placementsToAdd == 0 {
            return slot.posterFrames.isEmpty ? "change the order" : "change the poster frame"
        }
        return "remove \(slot.toRemove.count), add \(slot.placementsToAdd)"
    }

    public var changingPreviewSets: [PreviewSetPlan] { previewSets.filter(\.changesAnything) }
    public var hasChanges: Bool {
        sets.contains(where: \.changesAnything) || previewSets.contains(where: \.changesAnything)
            || creativeSets.contains(where: \.plan.changesAnything)
    }

    public var imagesToAdd: Int {
        sets.reduce(0) { total, item in
            guard case let .replace(_, adding) = item.action else { return total }
            return total + adding
        }
    }

    public var imagesToRemove: Int {
        sets.reduce(0) { total, item in
            guard case let .replace(removing, _) = item.action else { return total }
            return total + removing
        }
    }
}

public enum ExperimentPlanner {
    /// Compares against the App Asset Library, through the record of what
    /// this project uploaded.
    public static func plan(
        local: ExperimentContent,
        config: ProjectConfig,
        remote: RemoteExperiments,
        record: AssetRecord = AssetRecord()
    ) -> ExperimentPlan {
        var sets: [ExperimentPlan.SetPlan] = []
        var previewSets: [ExperimentPlan.PreviewSetPlan] = []
        var creativeSets: [ExperimentPlan.CreativeSetPlan] = []
        var placed: Set<ExperimentSlot> = []
        let deviceClasses = config.resolvedDeviceClasses
        let experimentNames = ExperimentFolders.folderNames(for: remote.experiments.map { ($0.id, $0.name) })

        for experiment in remote.experiments {
            let experimentFolder = experimentNames[experiment.id] ?? experiment.name
            let treatmentNames = ExperimentFolders.folderNames(for: experiment.treatments.map { ($0.id, $0.name) })

            for treatment in experiment.treatments {
                let treatmentFolder = treatmentNames[treatment.id] ?? treatment.name

                for localization in treatment.localizations.sorted(by: { $0.locale < $1.locale }) {
                    do {
                        creativeSets += creativePlans(
                            in: local.creative["\(experimentFolder)/\(treatmentFolder)"] ?? CreativeFolder(),
                            label: "\(experiment.name) / \(treatment.name) / \(localization.locale)",
                            treatmentID: treatment.id, localization: localization,
                            config: config, record: record
                        )
                        previewSets += previewPlans(
                            experiment: experiment, treatment: treatment, localization: localization,
                            folders: (experimentFolder, treatmentFolder),
                            local: local, deviceClasses: deviceClasses, record: record
                        )
                    }
                    for deviceClass in deviceClasses {
                        let slot = ExperimentSlot(
                            experiment: experimentFolder,
                            treatment: treatmentFolder,
                            locale: localization.locale,
                            deviceClassID: deviceClass.id
                        )
                        let files = local.screenshots(in: slot)
                        let library = LibraryPlanner.slot(
                            files: files.map(\.libraryFile),
                            current: LibraryPlanner.current(
                                in: localization.placements,
                                locale: localization.locale,
                                group: deviceClass.placementGroup,
                                type: deviceClass.screenshotPlacementType
                            ),
                            record: record,
                            group: deviceClass.placementGroup,
                            type: deviceClass.screenshotPlacementType
                        )

                        guard files.isEmpty == false || library.current.isEmpty == false else { continue }
                        placed.insert(slot)

                        sets.append(.init(
                            experimentID: experiment.id,
                            experimentName: experiment.name,
                            treatmentID: treatment.id,
                            treatmentName: treatment.name,
                            locale: localization.locale,
                            treatmentLocalizationID: localization.id,
                            deviceClass: deviceClass,
                            localFiles: files,
                            library: library
                        ))
                    }
                }
            }
        }

        return ExperimentPlan(
            sets: sets,
            unplaced: unplaced(local: local, placed: placed, remote: remote),
            previewSets: previewSets,
            creativeSets: creativeSets
        )
    }

    // swiftlint:disable:next function_parameter_count
    private static func creativePlans(
        in folder: CreativeFolder,
        label: String,
        treatmentID: String,
        localization: RemoteTreatmentLocalization,
        config: ProjectConfig,
        record: AssetRecord
    ) -> [ExperimentPlan.CreativeSetPlan] {
        CreativePlanner.plans(
            folder: folder, locales: [localization.locale], placements: localization.placements,
            record: record
        ).map {
            ExperimentPlan.CreativeSetPlan(
                treatmentID: treatmentID, label: label, treatmentLocalizationID: localization.id, plan: $0
            )
        }
    }

    // swiftlint:disable:next function_parameter_count
    private static func previewPlans(
        experiment: RemoteExperiment,
        treatment: RemoteTreatment,
        localization: RemoteTreatmentLocalization,
        folders: (experiment: String, treatment: String),
        local: ExperimentContent,
        deviceClasses: [DeviceClass],
        record: AssetRecord
    ) -> [ExperimentPlan.PreviewSetPlan] {
        deviceClasses.filter(\.takesPreviews).compactMap { deviceClass in
            let files = local.previews(in: ExperimentSlot(
                experiment: folders.experiment, treatment: folders.treatment,
                locale: localization.locale, deviceClassID: deviceClass.id
            ))
            let current = LibraryPlanner.current(
                in: localization.placements, locale: localization.locale,
                group: deviceClass.placementGroup, type: .appPreview
            )
            guard files.isEmpty == false || current.isEmpty == false else { return nil }

            return ExperimentPlan.PreviewSetPlan(
                experimentName: experiment.name,
                treatmentID: treatment.id,
                treatmentName: treatment.name,
                locale: localization.locale,
                treatmentLocalizationID: localization.id,
                deviceClass: deviceClass,
                localFiles: files,
                library: LibraryPlanner.slot(
                    files: files.map(\.libraryFile), current: current, record: record,
                    group: deviceClass.placementGroup, type: .appPreview
                )
            )
        }
    }

    /// Folders holding images that nothing will upload, and why.
    private static func unplaced(
        local: ExperimentContent,
        placed: Set<ExperimentSlot>,
        remote: RemoteExperiments
    ) -> [ExperimentPlan.Unplaced] {
        let experimentNames = ExperimentFolders.folderNames(for: remote.experiments.map { ($0.id, $0.name) })
        var result: [ExperimentPlan.Unplaced] = []

        for (slot, files) in local.screenshots where files.isEmpty == false && placed.contains(slot) == false {
            let reason: ExperimentPlan.Unplaced.Reason
            let experiment = remote.experiments.first { experimentNames[$0.id] == slot.experiment }
            if let experiment {
                let names = ExperimentFolders.folderNames(for: experiment.treatments.map { ($0.id, $0.name) })
                if let treatment = experiment.treatments.first(where: { names[$0.id] == slot.treatment }) {
                    reason = treatment.localization(slot.locale) == nil ? .noLanguage : .deviceClassNotListed
                } else {
                    reason = .noTreatment
                }
            } else {
                reason = .noDraftExperiment
            }
            result.append(.init(slot: slot, imageCount: files.count, reason: reason))
        }
        return result.sorted { $0.id < $1.id }
    }
}
