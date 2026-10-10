import ASCKitAPI
import Foundation

/// What the last read of App Store Connect found in the tests that are not
/// over, kept in `cache/`.
///
/// A caller with no network and no key reads this to know that a test and
/// its treatments exist. Never in the repository, like the rest of the
/// cache.
public struct ExperimentSnapshot: Codable, Sendable, Equatable {
    public struct Experiment: Codable, Sendable, Equatable {
        public let name: String
        /// The folder under `product-page-optimization`.
        public let folder: String
        public let platform: String?
        /// The raw state, such as `PREPARE_FOR_SUBMISSION`.
        public let state: String?
        /// Whether its treatments take images.
        public let isEditable: Bool
        public let treatments: [Treatment]
    }

    public struct Treatment: Codable, Sendable, Equatable {
        public let name: String
        public let folder: String
        /// The languages App Store Connect holds a page for in this treatment.
        public let locales: [String]
    }

    public let readOn: Date
    public let experiments: [Experiment]

    public init(_ remote: RemoteExperiments, readOn: Date = .now) {
        let experimentNames = ExperimentFolders.folderNames(for: remote)
        self.readOn = readOn
        experiments = remote.experiments.map { experiment in
            let treatmentNames = ExperimentFolders.folderNames(for: experiment.treatments.map { ($0.id, $0.name) })
            return Experiment(
                name: experiment.name,
                folder: experimentNames[experiment.id] ?? experiment.name,
                platform: experiment.platform?.rawValue,
                state: experiment.state?.rawValue,
                isEditable: experiment.isEditable,
                treatments: experiment.treatments.map {
                    Treatment(
                        name: $0.name,
                        folder: treatmentNames[$0.id] ?? $0.name,
                        locales: $0.localizations.map(\.locale).sorted()
                    )
                }
            )
        }
    }
}

public extension ExperimentSnapshot.Experiment {
    /// A cache from before 0.4.0 holds no state and only draft tests, so a
    /// test with no `isEditable` is editable.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(
            name: container.decode(String.self, forKey: .name),
            folder: container.decode(String.self, forKey: .folder),
            platform: container.decodeIfPresent(String.self, forKey: .platform),
            state: container.decodeIfPresent(String.self, forKey: .state),
            isEditable: container.decodeIfPresent(Bool.self, forKey: .isEditable) ?? true,
            treatments: container.decode([ExperimentSnapshot.Treatment].self, forKey: .treatments)
        )
    }
}

public enum ExperimentSnapshotStore {
    public static func url(in project: Project) -> URL {
        project.cacheURL.appending(path: "experiments.json")
    }

    /// Nil until something has read the draft tests.
    public static func load(in project: Project) -> ExperimentSnapshot? {
        guard let data = try? Data(contentsOf: url(in: project)) else { return nil }
        return try? ProjectJSON.decoder(datesAsISO8601: true).decode(ExperimentSnapshot.self, from: data)
    }

    public static func save(_ snapshot: ExperimentSnapshot, in project: Project) throws {
        let url = url(in: project)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try ProjectJSON.write(snapshot, to: url, datesAsISO8601: true)
    }
}
