import ASCKitAPI
import Foundation

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
                            in: local.creative[ExperimentContent.creativeKey(
                                experiment: experimentFolder, treatment: treatmentFolder
                            )] ?? CreativeFolder(),
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
