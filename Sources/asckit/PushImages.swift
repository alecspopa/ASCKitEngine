import ArgumentParser
import ASCKitAPI
import ASCKitProject
import Foundation

struct PushImages: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "images",
        abstract: "Upload the screenshots. Touches no text.",
        discussion: """
        The images go into the app's asset library. Each file goes up once, \
        however many languages use it, and asset-library.json in the project folder records \
        it. A slot that already holds the right images keeps them. A placement \
        that goes leaves its image in the library, so nothing is lost. \
        asckit library prune deletes what nothing places.

        Previews and the header and search results art go the same way.
        """
    )

    @OptionGroup var options: ProjectOptions

    @Flag(name: .long, help: "Do not ask. Use only for a plan you have already read.")
    var yes = false

    func run() async throws {
        let project = try options.loadProject()

        let checked = try Checker.check(project: project, version: options.appVersion)
        try stopOnScreenshotErrors(checked, project: project)

        let session = try makeSession(for: project)
        let reading = try await session.read(version: options.appVersion)
        let listing = reading.listing
        let plan = try VersionCheck.plan(in: reading, project: project)

        print(versionHeader(listing, plan))
        print("")
        for line in ChangePlanFormatter.lines(for: plan) {
            print(line)
        }

        guard plan.hasScreenshotChanges else {
            print("No screenshot changes.")
            return
        }

        if plan.blocked(.screenshots).isEmpty == false {
            throw PushError.blocked(plan.blocked(.screenshots))
        }

        print(ChangePlanFormatter.summary(plan))

        guard confirmed(yes: yes, "Upload these to App Store Connect?") else {
            throw ExitCode.failure
        }

        let outcome = try await session.pushImages(reading) { step in
            print("  \(step.label)")
        }
        report(outcome.result)
        reportReceipt(outcome, project: project)

        if outcome.result.isCompleteSuccess == false { throw ExitCode.failure }
    }

    /// Text problems do not stop an image push. Anything wrong with the images
    /// does, because uploading a wrong size just gets it refused later.
    private func stopOnScreenshotErrors(_ checked: CheckResult, project: Project) throws {
        let relevant = checked.errors.filter { $0.area == .screenshots || $0.area == .configuration }
        try stopOnErrors(relevant, project: project)
    }

    private func report(_ result: ScreenshotPusher.Result) {
        reportImages(result, readBack: "Read it back with asckit diff.")
    }
}
