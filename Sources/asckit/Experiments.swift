import ArgumentParser
import ASCKitAPI
import ASCKitProject
import Foundation

private let noDraftTest = """
There is no draft test on App Store Connect. Make a test in App Store Connect first. \
ASCKit never makes one.
"""

// MARK: - Read

struct Experiments: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "experiments",
        abstract: "Read the draft Product Page Optimization tests, and make a folder for each.",
        discussion: """
        Reads the draft tests from App Store Connect and writes nothing to it. It makes an \
        empty folder in \(ExperimentFolders.folderName)/ for each language of each treatment.

        To change the images of a treatment, drop the images in its folder and run \
        asckit push-experiment-images. Or drop them in \
        inbox/\(ExperimentFolders.folderName)/<test>/<treatment>/ and run asckit inbox --file.

        ASCKit never makes a test, a treatment or a language of a treatment. Make those in \
        App Store Connect, then run this command again.
        """
    )

    @OptionGroup var options: ProjectOptions

    func run() async throws {
        let project = try options.loadProject()
        let session = try makeSession(for: project)
        let reading = try await session.readExperiments()

        guard reading.remote.experiments.isEmpty == false else {
            print(noDraftTest)
            return
        }

        ExperimentReport.print(reading, project: project)

        if reading.plan.hasChanges {
            print("")
            print("Run asckit push-experiment-images to upload these.")
        }
    }
}

enum ExperimentReport {
    static func print(_ reading: PushSession.ExperimentReading, project: Project) {
        let plan = reading.plan

        for experiment in reading.remote.experiments {
            Swift.print("\(experiment.name), \(experiment.state?.rawValue ?? unknownState)")

            for treatment in experiment.treatments {
                Swift.print("  \(treatment.name)")
                let locales = treatment.localizations.map(\.locale).sorted()
                Swift.print("    languages: \(locales.isEmpty ? "none" : locales.joined(separator: ", "))")

                let sets = plan.sets.filter {
                    $0.experimentID == experiment.id && $0.treatmentID == treatment.id
                }
                for set in sets where set.changesAnything {
                    Swift.print("    \(set.locale)/\(set.deviceClass.id): \(describe(set.action))")
                }
                let library = plan.libraryLines(treatmentID: treatment.id)
                for line in library {
                    Swift.print("    \(line)")
                }
                if sets.contains(where: \.changesAnything) == false, library.isEmpty {
                    Swift.print("    no image changes")
                }
            }
            Swift.print("")
        }

        if plan.hasChanges {
            Swift.print("A push would add \(plan.imagesToAdd) and remove \(plan.imagesToRemove).")
        } else {
            Swift.print("A push would change nothing.")
        }

        if plan.unplaced.isEmpty == false {
            Swift.print("")
            Swift.print("These folders hold images with no place to go:")
            for item in plan.unplaced {
                Swift.print("  \(ExperimentFolders.folderName)/\(item.slot.experiment)/\(item.slot.treatment)"
                    + "/\(item.slot.locale)/\(item.slot.deviceClassID), \(countedNoun(item.imageCount, "image")): \(reason(item.reason))")
            }
        }

        if reading.madeFolders.isEmpty == false {
            Swift.print("")
            Swift.print("Made \(countedNoun(reading.madeFolders.count, "empty folder")) in "
                + "\(ExperimentFolders.folderName)/. Drop the images in them.")
        }
    }

    static func describe(_ action: ChangePlan.ScreenshotPlan.Action) -> String {
        switch action {
        case .unchanged: "unchanged"
        case let .replace(removing, adding): "remove \(removing), add \(adding)"
        }
    }

    static func reason(_ reason: ExperimentPlan.Unplaced.Reason) -> String {
        switch reason {
        case .noDraftExperiment: "no draft test has this name. It is finished, or it never existed."
        case .noTreatment: "the test has no treatment with this name."
        case .noLanguage: "the treatment has no page for this language. Add it in App Store Connect."
        case .deviceClassNotListed: "this project does not list the device class."
        }
    }
}

// MARK: - Push

struct PushExperimentImages: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "push-experiment-images",
        abstract: "Upload the images of the draft Product Page Optimization tests.",
        discussion: """
        Drop the images in \(ExperimentFolders.folderName)/<test>/<treatment>/<language>/<device class>/, \
        then run this command. Run asckit experiments first to make the folders.

        The images go into the app's asset library, each file once, and are placed on each \
        treatment's languages. A placement taken off leaves its image in the library.

        ASCKit never makes a test, a treatment or a language of a treatment.
        """
    )

    @OptionGroup var options: ProjectOptions

    @Flag(name: .long, help: "Do not ask. Use only for a plan you have already read.")
    var yes = false

    func run() async throws {
        let project = try options.loadProject()
        let session = try makeSession(for: project)
        let reading = try await session.readExperiments()

        guard reading.remote.experiments.isEmpty == false else {
            print(noDraftTest)
            return
        }

        // Same rule as asckit check: a wrong size is refused later anyway.
        let problems = Validator(project: project).validate(reading.content)
            .filter { $0.severity == .error }
        try stopOnErrors(problems, project: project)

        ExperimentReport.print(reading, project: project)

        guard reading.plan.hasChanges else {
            print("No image changes.")
            return
        }

        guard confirmed(yes: yes, "Upload these to App Store Connect?") else {
            throw ExitCode.failure
        }

        let outcome = await session.pushExperimentImages(reading) { step in
            print("  \(step.label)")
        }
        let result = outcome.result

        reportImages(result, readBack: "Run asckit experiments to read it back.")
        reportReceipt(outcome, project: project)

        if result.isCompleteSuccess == false { throw ExitCode.failure }
    }
}
