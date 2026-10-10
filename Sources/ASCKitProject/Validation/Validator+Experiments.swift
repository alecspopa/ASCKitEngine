import ASCKitAPI
import Foundation

extension Validator {
    /// The languages of a treatment that have no screenshots for a device
    /// class that another language of the same treatment has.
    ///
    /// App Store Connect shows the original product page's screenshots for a
    /// language with none, so that language tests nothing. It accepts this,
    /// so it is a warning. A treatment with no screenshots in any language
    /// tests only the icon or the art, and that says nothing.
    ///
    /// The snapshot says which languages a treatment has, and which sets App
    /// Store Connect already holds. Without it nothing is checked.
    func validateTreatmentLanguages(_ experiments: ExperimentContent, snapshot: ExperimentSnapshot?) -> [Problem] {
        guard let snapshot else { return [] }
        var problems: [Problem] = []

        for experiment in snapshot.experiments where experiment.isEditable {
            let platform = experiment.platform.map(Platform.init(rawValue:))
            for treatment in experiment.treatments {
                let place = LibraryContentPlace.treatment(experiment: experiment.folder, treatment: treatment.folder)
                let locales = treatment.locales.filter { config.isIgnored($0) == false }

                for deviceClass in config.screenshotDeviceClasses(for: place, platform: platform) {
                    let slots = locales.map {
                        ExperimentSlot(
                            experiment: experiment.folder, treatment: treatment.folder,
                            locale: $0, deviceClassID: deviceClass.id
                        )
                    }
                    // After a push: the files, or what App Store Connect holds
                    // when the folder was not emptied on purpose.
                    let holding = slots.filter { slot in
                        experiments.screenshots(in: slot).isEmpty == false
                            || (experiments.emptied.contains(slot) == false
                                && treatment.holdsScreenshots(locale: slot.locale, deviceClass: deviceClass))
                    }
                    guard holding.isEmpty == false else { continue }

                    // A set emptied on purpose is a decision, so it says nothing.
                    for slot in slots where holding.contains(slot) == false && experiments.emptied.contains(slot) == false {
                        problems.append(missingTreatmentScreenshots(
                            treatment: treatment.name, slot: slot, deviceClass: deviceClass
                        ))
                    }
                }
            }
        }
        return problems
    }

    private func missingTreatmentScreenshots(treatment: String, slot: ExperimentSlot, deviceClass: DeviceClass) -> Problem {
        let folder = slot.place.screenshotsPath(config: config, locale: slot.locale, deviceClassID: deviceClass.id)
        return Problem(
            severity: .warning,
            area: .screenshots,
            message: LocalizedStringResource(
                "\(treatment) has no \(deviceClass.displayName) screenshots in \(slot.locale).",
                bundle: .here
            ),
            fix: LocalizedStringResource("""
            App Store Connect shows the screenshots of the original product page there, \
            so this language does not test them. Put \(slot.locale) screenshots in \(folder).
            """, bundle: .here),
            locale: slot.locale,
            deviceClassID: deviceClass.id,
            path: folder,
            kind: .treatmentScreenshotsMissing
        )
    }
}
