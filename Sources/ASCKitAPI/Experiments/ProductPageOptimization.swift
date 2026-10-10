import Foundation

/// The state of a Product Page Optimization test.
///
/// A wrapper around a raw string for the reason `AppVersionState` is one:
/// Apple adds values.
public struct ExperimentState: RawRepresentable, Sendable, Hashable, Codable {
    public let rawValue: String
    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static let prepareForSubmission = Self(rawValue: "PREPARE_FOR_SUBMISSION")
    public static let readyForReview = Self(rawValue: "READY_FOR_REVIEW")
    public static let waitingForReview = Self(rawValue: "WAITING_FOR_REVIEW")
    public static let inReview = Self(rawValue: "IN_REVIEW")
    public static let accepted = Self(rawValue: "ACCEPTED")
    public static let approved = Self(rawValue: "APPROVED")
    public static let rejected = Self(rawValue: "REJECTED")
    public static let completed = Self(rawValue: "COMPLETED")
    public static let stopped = Self(rawValue: "STOPPED")

    /// The states whose treatments take images: a test nobody has sent to
    /// review yet, and a test review sent back. Every other state refuses them.
    public static let editable: Set<Self> = [.prepareForSubmission, .rejected]

    /// Every state a read asks for. A completed or stopped test is over, so a
    /// read leaves it out. A state Apple adds later is left out until it is
    /// named here.
    static let unfinished: [Self] = [
        .prepareForSubmission, .readyForReview, .waitingForReview, .inReview,
        .accepted, .approved, .rejected
    ]

    public var isEditable: Bool { Self.editable.contains(self) }
}

public struct ExperimentAttributes: Decodable, Sendable {
    public let name: String?
    public let state: ExperimentState?
    public let platform: Platform?
    public let trafficProportion: Int?
}

public struct TreatmentAttributes: Decodable, Sendable {
    public let name: String?
}

public struct TreatmentLocalizationAttributes: Decodable, Sendable {
    public let locale: String?
}

public extension ASCClient {
    /// Every test of an app that is not over yet.
    ///
    /// Asked of App Store Connect with a filter, so a long history of finished
    /// tests is not read for the few that are not.
    func experiments(appID: String) async throws -> [Resource<ExperimentAttributes>] {
        try await list(
            "/v1/apps/\(appID)/appStoreVersionExperimentsV2",
            query: [URLQueryItem(
                name: "filter[state]",
                value: ExperimentState.unfinished.map(\.rawValue).joined(separator: ",")
            )],
            as: ExperimentAttributes.self
        )
    }

    func treatments(experimentID: String) async throws -> [Resource<TreatmentAttributes>] {
        try await list(
            "/v2/appStoreVersionExperiments/\(experimentID)/appStoreVersionExperimentTreatments",
            as: TreatmentAttributes.self
        )
    }

    func treatmentLocalizations(
        treatmentID: String
    ) async throws -> [Resource<TreatmentLocalizationAttributes>] {
        try await list(
            "/v1/appStoreVersionExperimentTreatments/\(treatmentID)/appStoreVersionExperimentTreatmentLocalizations",
            as: TreatmentLocalizationAttributes.self
        )
    }
}

// MARK: - What App Store Connect holds

/// The tests of one app that are not over, with everything a push needs to
/// write into the editable ones.
public struct RemoteExperiments: Sendable {
    public let appID: String
    public let experiments: [RemoteExperiment]

    public init(appID: String, experiments: [RemoteExperiment]) {
        self.appID = appID
        self.experiments = experiments
    }
}

public struct RemoteExperiment: Sendable, Identifiable {
    public let id: String
    public let name: String
    public let state: ExperimentState?
    public let platform: Platform?
    public let treatments: [RemoteTreatment]

    public init(
        id: String,
        name: String,
        state: ExperimentState?,
        platform: Platform?,
        treatments: [RemoteTreatment]
    ) {
        self.id = id
        self.name = name
        self.state = state
        self.platform = platform
        self.treatments = treatments
    }

    /// Whether its treatments take images. A test with no state is locked.
    public var isEditable: Bool { state?.isEditable == true }
}

public struct RemoteTreatment: Sendable, Identifiable {
    public let id: String
    public let name: String
    public let localizations: [RemoteTreatmentLocalization]

    public init(id: String, name: String, localizations: [RemoteTreatmentLocalization]) {
        self.id = id
        self.name = name
        self.localizations = localizations
    }

    public func localization(_ locale: String) -> RemoteTreatmentLocalization? {
        localizations.first { $0.locale == locale }
    }
}

public struct RemoteTreatmentLocalization: Sendable, Identifiable {
    public let id: String
    public let locale: String
    /// The library assets placed on this language, in the store's order.
    public let placements: [RemotePlacement]

    public init(id: String, locale: String, placements: [RemotePlacement] = []) {
        self.id = id
        self.locale = locale
        self.placements = placements
    }
}

public extension ASCClient {
    /// Reads the tests of an app that are not over: each one's treatments,
    /// their languages and the library assets placed on them. A locked test
    /// is read too, so a page can show what App Store Connect holds.
    ///
    /// Nothing is made. A test, a treatment and a language of a treatment all
    /// come from App Store Connect, and ASCKit only places assets on them.
    func experiments(bundleID: String) async throws -> RemoteExperiments {
        guard let app = try await app(bundleID: bundleID) else {
            throw ListingError.noSuchApp(bundleID: bundleID)
        }

        var experiments: [RemoteExperiment] = []
        // App Store Connect answered a COMPLETED test to the state filter on
        // 2026-10-10, so the state is checked here as well.
        let unfinished = try await self.experiments(appID: app.id).filter { experiment in
            experiment.attributes?.state.map(ExperimentState.unfinished.contains) == true
        }
        for experiment in unfinished {
            var treatments: [RemoteTreatment] = []
            for treatment in try await self.treatments(experimentID: experiment.id) {
                let localizations = try await readTreatmentLocalizations(treatmentID: treatment.id)
                treatments.append(RemoteTreatment(
                    id: treatment.id,
                    name: treatment.attributes?.name ?? treatment.id,
                    localizations: localizations
                ))
            }
            experiments.append(RemoteExperiment(
                id: experiment.id,
                name: experiment.attributes?.name ?? experiment.id,
                state: experiment.attributes?.state,
                platform: experiment.attributes?.platform,
                treatments: treatments.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            ))
        }

        // By name, because App Store Connect answers in no order a person can
        // rely on. "Treatment A" comes before "Treatment B" everywhere.
        return RemoteExperiments(
            appID: app.id,
            experiments: experiments.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        )
    }

    /// Languages are read together, because a treatment in eleven languages is
    /// otherwise eleven round trips waiting on each other.
    private func readTreatmentLocalizations(
        treatmentID: String
    ) async throws -> [RemoteTreatmentLocalization] {
        let resources = try await treatmentLocalizations(treatmentID: treatmentID)

        let outcomes = await withTaskGroup(
            of: Result<RemoteTreatmentLocalization?, any Error>.self
        ) { group in
            for resource in resources {
                group.addTask {
                    await Self.captured {
                        guard let locale = resource.attributes?.locale else { return nil }
                        let placements = try await readPlacements(
                            on: .treatmentLocalization(id: resource.id), locale: locale
                        )
                        return RemoteTreatmentLocalization(id: resource.id, locale: locale, placements: placements)
                    }
                }
            }
            var collected: [Result<RemoteTreatmentLocalization?, any Error>] = []
            for await outcome in group {
                collected.append(outcome)
            }
            return collected
        }

        return try Self.unwrap(outcomes).compactMap(\.self).sorted { $0.locale < $1.locale }
    }
}
