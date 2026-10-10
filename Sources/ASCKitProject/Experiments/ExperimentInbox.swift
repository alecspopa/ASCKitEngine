import ASCKitAPI
import Foundation

/// Images waiting to go into a treatment of a draft Product Page Optimization
/// test.
///
///     inbox/product-page-optimization/<test>/<treatment>/03-shopping-iPhone-6.9-en_US.png
///
/// The two folders say which treatment. The file name says the language and
/// the device class, in the same format as every other waiting image, so an
/// export that works for the App Store page works here too. Folders deeper
/// than the treatment say nothing extra.
///
/// The folder names are the ones `ExperimentFolders` makes. Reading App Store
/// Connect makes them under `product-page-optimization`, and the same names
/// work here.
public enum ExperimentInbox {
    public static func url(in project: Project) -> URL {
        Inbox.url(in: project).appending(path: ExperimentFolders.folderName)
    }

    /// What one waiting image would do.
    public struct Arrival: Sendable, Hashable, Identifiable {
        public let file: ScreenshotFile
        public let slot: ExperimentSlot
        public let deviceClass: DeviceClass
        public let imageName: String
        public var id: URL { file.url }
    }

    public struct Refusal: Sendable, Hashable, Identifiable {
        public let file: ScreenshotFile
        public let reason: String

        /// Whether an alpha channel is the whole reason, as in `Inbox.Refusal`.
        public var hasClearableAlpha = false

        public var id: URL { file.url }
    }

    public struct Plan: Sendable, Hashable {
        public var arrivals: [Arrival] = []
        public var refusals: [Refusal] = []

        public var isEmpty: Bool { arrivals.isEmpty && refusals.isEmpty }

        /// The arrivals that go into one slot.
        public struct Group: Sendable {
            public let slot: ExperimentSlot
            public let deviceClass: DeviceClass
            public var arrivals: [Arrival]
        }

        /// The arrivals gathered by slot, in the order they arrived. One slot
        /// is written at a time, because the limit of ten is counted per slot.
        public var groups: [Group] {
            var groups: [Group] = []
            for arrival in arrivals {
                if let index = groups.firstIndex(where: { $0.slot == arrival.slot }) {
                    groups[index].arrivals.append(arrival)
                } else {
                    groups.append(Group(slot: arrival.slot, deviceClass: arrival.deviceClass, arrivals: [arrival]))
                }
            }
            return groups
        }
    }

    /// The images waiting under the folder, in name order.
    public static func waiting(in project: Project) -> [ScreenshotFile] {
        let entries = FileManager.default.enumerator(
            at: url(in: project),
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        )?.compactMap { $0 as? URL } ?? []

        return entries
            .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false }
            .sortedNaturally(by: \.path)
            .map(ImageInspector.inspect)
            .filter { $0.pixelWidth != nil }
    }

    /// Reads the folder and works out where each image goes.
    ///
    /// A treatment folder must already exist under `product-page-optimization`
    /// or be one of the names in `remote`. ASCKit never makes a treatment, so
    /// an image in a folder that names none is refused with the names that do
    /// exist.
    public static func plan(in project: Project, remote: RemoteExperiments? = nil) -> Plan {
        var known: [String: Set<String>] = [:]
        var locked: [String: String] = [:]
        let onDisk = ExperimentContentStore.load(in: project)
        for slot in onDisk.screenshots.keys {
            known[slot.experiment, default: []].insert(slot.treatment)
        }
        if let remote {
            let experimentNames = ExperimentFolders.folderNames(for: remote)
            for experiment in remote.experiments {
                let folder = experimentNames[experiment.id] ?? experiment.name
                guard experiment.isEditable else {
                    locked[folder] = experiment.state?.rawValue ?? ""
                    continue
                }
                let names = ExperimentFolders.folderNames(for: experiment.treatments.map { ($0.id, $0.name) })
                known[folder, default: []].formUnion(names.values)
            }
        }
        return plan(waiting(in: project), root: url(in: project), known: known, locked: locked,
                    config: project.config, refData: RefDataCache.load(in: project))
    }

    /// The same, with the treatments the last read of App Store Connect found.
    ///
    /// For a caller with no network and no key, whose cache holds the names. A treatment with no folder yet still takes images.
    public static func plan(in project: Project, snapshot: ExperimentSnapshot?) -> Plan {
        var known: [String: Set<String>] = [:]
        var locked: [String: String] = [:]
        for slot in ExperimentContentStore.load(in: project).screenshots.keys {
            known[slot.experiment, default: []].insert(slot.treatment)
        }
        for experiment in snapshot?.experiments ?? [] {
            guard experiment.isEditable else {
                locked[experiment.folder] = experiment.state ?? ""
                continue
            }
            known[experiment.folder, default: []].formUnion(experiment.treatments.map(\.folder))
        }
        return plan(waiting(in: project), root: url(in: project), known: known, locked: locked,
                    config: project.config, refData: RefDataCache.load(in: project))
    }

    /// `locked` holds the folder and the raw state of each test that takes no
    /// images. Its folder can exist on disk, so it is refused before `known`.
    static func plan(
        _ files: [ScreenshotFile],
        root: URL,
        known: [String: Set<String>],
        locked: [String: String] = [:],
        config: ProjectConfig,
        refData: AssetLibraryRefData? = nil
    ) -> Plan {
        var plan = Plan()
        let rootParts = root.standardizedFileURL.pathComponents

        for file in files {
            let parts = Array(file.url.standardizedFileURL.pathComponents.dropFirst(rootParts.count))
            // Test folder, treatment folder, and the file itself.
            guard parts.count >= 3 else {
                plan.refusals.append(Refusal(file: file, reason: String(
                    localized: """
                    \(file.fileName) is not in a treatment folder. Put it in \
                    \(ExperimentFolders.folderName)/<test>/<treatment>/.
                    """, bundle: .module
                )))
                continue
            }
            let experiment = parts[0], treatment = parts[1]

            if let state = locked[experiment] {
                plan.refusals.append(Refusal(file: file, reason: String(
                    localized: """
                    The test \(experiment) is \(state) on App Store Connect. Only a test in \
                    Prepare for Submission or Rejected takes images.
                    """, bundle: .module
                )))
                continue
            }

            guard let treatments = known[experiment], treatments.contains(treatment) else {
                let names = known.flatMap { test, items in items.map { "\(test)/\($0)" } }.sorted()
                plan.refusals.append(Refusal(file: file, reason: String(
                    localized: """
                    \(experiment)/\(treatment) is not a treatment of a draft test. \
                    Read App Store Connect to make the folders. Known: \(names.joined(separator: ", ")).
                    """, bundle: .module
                )))
                continue
            }

            switch ScreenshotNaming.read(file.fileName, config: config) {
            case let .success(named):
                if let refused = ContentWriter.inboxRefusal(file, for: named.deviceClass, refData: refData) {
                    plan.refusals.append(Refusal(
                        file: file, reason: refused.reason, hasClearableAlpha: refused.hasClearableAlpha
                    ))
                } else {
                    plan.arrivals.append(Arrival(
                        file: file,
                        slot: ExperimentSlot(
                            experiment: experiment,
                            treatment: treatment,
                            locale: named.locale,
                            deviceClassID: named.deviceClass.id
                        ),
                        deviceClass: named.deviceClass,
                        imageName: named.imageName
                    ))
                }
            case let .failure(refusal):
                plan.refusals.append(Refusal(file: file, reason: refusal.description))
            }
        }
        return plan
    }

    /// What filing did.
    public struct Outcome: Sendable {
        public var filed: Int
        public var slots: [ExperimentSlot]

        /// Where replaced files went, so a caller can point at them.
        public var trashed: [URL]
    }

    /// Puts each accepted image in its treatment's folder and moves the inbox
    /// copy to the Trash. The inbox copy may be the only copy of that artwork.
    @discardableResult
    public static func file(
        _ plan: Plan,
        replacingExisting: Bool = false,
        in project: Project
    ) throws -> Outcome {
        var outcome = Outcome(filed: 0, slots: [], trashed: [])

        for group in plan.groups {
            let written = try ContentWriter.addScreenshots(
                from: group.arrivals.map(\.file.url),
                locale: group.slot.locale,
                deviceClass: group.deviceClass,
                at: group.slot.place,
                replacingExisting: replacingExisting,
                in: project
            )
            outcome.trashed += written.trashed

            for arrival in group.arrivals {
                var landed: NSURL?
                try FileManager.default.trashItem(at: arrival.file.url, resultingItemURL: &landed)
                if let landed = landed as URL? { outcome.trashed.append(landed) }
            }
            outcome.filed += group.arrivals.count
            outcome.slots.append(group.slot)
        }
        return outcome
    }
}
