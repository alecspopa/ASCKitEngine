import ASCKitAPI
import Foundation

/// What the last read of App Store Connect found in the draft tests, kept in
/// `cache/`.
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
        let experimentNames = ExperimentFolders.folderNames(for: remote.experiments.map { ($0.id, $0.name) })
        self.readOn = readOn
        experiments = remote.experiments.map { experiment in
            let treatmentNames = ExperimentFolders.folderNames(for: experiment.treatments.map { ($0.id, $0.name) })
            return Experiment(
                name: experiment.name,
                folder: experimentNames[experiment.id] ?? experiment.name,
                platform: experiment.platform?.rawValue,
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
