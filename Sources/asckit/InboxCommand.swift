import ArgumentParser
import ASCKitAPI
import ASCKitProject
import Foundation

/// The terminal's way into the same folder the app watches.
///
/// Both go through `Inbox`, which reads every name through
/// `ScreenshotNaming`, so a file that lands in `de-DE` here lands in `de-DE`
/// in the window as well.
struct InboxCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "inbox",
        abstract: "Show what is waiting in inbox/, and file it.",
        discussion: """
        Every waiting file is named \(ScreenshotNaming.example): the number is where it goes \
        in the set, then what the screenshot shows, then the device class, then the language. \
        The name says where the image belongs, so nothing is asked.

        Shows what would happen and writes nothing. Pass --file to move the images in. \
        The inbox copy goes to the Trash rather than being deleted.

        --file reads App Store Connect first. A version that takes no screenshots, such as \
        the version on sale, is refused and nothing moves.

        A file for a device class this project does not list is refused. \
        --adopt-devices puts that device class in the list first, so screenshots for a \
        device the app has started shipping on go in without being renamed.

        A header or search results image is named \(ScreenshotNaming.creativeExample) or \
        search-results-en_US.png: the role, then the language. It takes the place of the file \
        that role has in that language.

        A file with an alpha channel is refused as well, because App Store Connect refuses \
        one. --clear-alpha writes those files again without the channel, on a white ground, \
        and puts the file as it arrived in the Trash.

        A language in copiesScreenshotsFrom takes the pictures filed into the language it \
        copies. File es-MX pictures and es-ES holds them too, when the es-MX set is the newer one.

        Exits non-zero when a waiting file cannot be filed.
        """
    )

    @OptionGroup var options: ProjectOptions

    @Flag(name: .long, help: "Move the images into the set, rather than only saying where they go.")
    var file = false

    @Flag(name: .long, help: "Add device classes the waiting files name to this project.")
    var adoptDevices = false

    @Flag(name: .long, help: "Write waiting files that carry an alpha channel again without one.")
    var clearAlpha = false

    func run() async throws {
        var project = try options.loadProject()
        var plan = Inbox.plan(in: project)

        if adoptDevices, DeviceClassAdoption.unlisted(in: plan).isEmpty == false {
            try adoptDeviceClasses(plan, project: project)

            // Read again, so the rest of this run says where the images go now
            // rather than why they could not go anywhere a moment ago.
            project = try options.loadProject()
            plan = Inbox.plan(in: project)
        }

        // After the device classes, because a file for a device class nobody
        // has listed is refused on its name, and what its pixels carry is only
        // read once that name leads somewhere.
        var experimentPlan = ExperimentInbox.plan(in: project, remote: nil)
        var customPagePlan = CustomPageInbox.plan(in: project, snapshot: CustomPageSnapshotStore.load(in: project))

        if clearAlpha {
            let files = AlphaRemoval.clearable(in: plan)
                + AlphaRemoval.clearable(in: experimentPlan)
                + AlphaRemoval.clearable(in: customPagePlan)
            if files.isEmpty == false {
                clearTheAlphaChannels(files)
                plan = Inbox.plan(in: project)
                experimentPlan = ExperimentInbox.plan(in: project, remote: nil)
                customPagePlan = CustomPageInbox.plan(in: project, snapshot: CustomPageSnapshotStore.load(in: project))
            }
        }

        guard plan.isEmpty == false || experimentPlan.isEmpty == false || customPagePlan.isEmpty == false else {
            print("Nothing is waiting in \(ProjectScaffold.inboxName)/.")
            return
        }

        // What the screenshot shows rather than the whole filed name, because
        // the number in front of it is decided by what is in the slot already.
        for arrival in plan.arrivals {
            print("\(arrival.file.fileName) -> \(arrival.locale)/\(arrival.deviceClass.id), "
                + "as \(arrival.imageName)")
        }
        for arrival in plan.creative {
            print("\(arrival.file.fileName) -> \(arrival.locale) \(arrival.role.rawValue)")
        }
        for refusal in plan.refusals {
            print("refused: \(refusal.reason)")
        }

        if file, plan.hasArrivals {
            try await fileEverything(plan, project: project)
        } else if file == false, plan.hasArrivals {
            print("")
            print("Nothing has moved. Run it again with --file to move these in.")
        }

        offerTheDeviceClasses(plan)
        offerToClearTheAlphaChannels(
            AlphaRemoval.clearable(in: plan)
                + AlphaRemoval.clearable(in: experimentPlan)
                + AlphaRemoval.clearable(in: customPagePlan)
        )

        let experimentsRefused = try handleExperiments(experimentPlan, project: project)
        let customPagesRefused = try handleCustomPages(customPagePlan, project: project)

        if plan.refusals.isEmpty == false || experimentsRefused || customPagesRefused { throw ExitCode.failure }
    }

    /// The images waiting for a custom product page. Returns true when one
    /// was refused.
    private func handleCustomPages(_ plan: CustomPageInbox.Plan, project: Project) throws -> Bool {
        guard plan.isEmpty == false else { return false }

        print("")
        print("Custom product pages, \(CustomPageFolders.folderName)/:")
        for arrival in plan.arrivals {
            print("\(arrival.file.fileName) -> \(arrival.slot.path), as \(arrival.imageName)")
        }
        for refusal in plan.refusals {
            print("refused: \(refusal.reason)")
        }

        if file, plan.arrivals.isEmpty == false {
            let outcome = try CustomPageInbox.file(plan, in: project)
            print("")
            print("Filed \(countedNoun(outcome.filed, "image")) into "
                + "\(countedNoun(outcome.slots.count, "page folder")).")
            print("The inbox copies are in the Trash. Run asckit push-custom-pages to upload them.")
        } else if plan.arrivals.isEmpty == false {
            print("")
            print("Nothing has moved. Run it again with --file to move these in.")
        }
        return plan.refusals.isEmpty == false
    }

    /// The images waiting for a Product Page Optimization test. Returns true
    /// when one was refused.
    private func handleExperiments(_ plan: ExperimentInbox.Plan, project: Project) throws -> Bool {
        guard plan.isEmpty == false else { return false }

        print("")
        print("Product Page Optimization, \(ExperimentFolders.folderName)/:")
        for arrival in plan.arrivals {
            print("\(arrival.file.fileName) -> \(arrival.slot.experiment)/\(arrival.slot.treatment)/"
                + "\(arrival.slot.locale)/\(arrival.deviceClass.id), as \(arrival.imageName)")
        }
        for refusal in plan.refusals {
            print("refused: \(refusal.reason)")
        }

        if file, plan.arrivals.isEmpty == false {
            let outcome = try ExperimentInbox.file(plan, in: project)
            print("")
            print("Filed \(countedNoun(outcome.filed, "image")) into "
                + "\(countedNoun(outcome.slots.count, "test folder")).")
            print("The inbox copies are in the Trash. Run asckit push-experiment-images to upload them.")
        } else if plan.arrivals.isEmpty == false {
            print("")
            print("Nothing has moved. Run it again with --file to move these in.")
        }
        return plan.refusals.isEmpty == false
    }

    /// Writes the waiting files that carry an alpha channel again without one.
    ///
    /// The same `AlphaRemoval` the window's inbox sheet presses, so a file
    /// cleared here and one cleared there end up the same.
    private func clearTheAlphaChannels(_ files: [ScreenshotFile]) {
        let outcome = AlphaRemoval.clear(files.map(\.url))

        for name in outcome.cleared {
            print("cleared: \(name)")
        }
        for failure in outcome.failed {
            print("could not clear: \(failure.fileName). \(failure.reason)")
        }
        if outcome.trashed.isEmpty == false {
            print("The files as they arrived are in the Trash.")
        }
        print("")
    }

    /// Says how to clear an alpha channel, for somebody reading a refusal about
    /// one.
    private func offerToClearTheAlphaChannels(_ waiting: [ScreenshotFile]) {
        guard waiting.isEmpty == false else { return }

        print("")
        print("Run it again with --clear-alpha to write \(countedNoun(waiting.count, "file")) "
            + "again without the channel.")
    }

    /// Puts the device classes the waiting files name into the project.
    ///
    /// The same `DeviceClassAdoption` the window's inbox sheet presses, so a
    /// device class taken in here and one taken in there leave the same
    /// `asckit.json` behind.
    private func adoptDeviceClasses(_ plan: Inbox.Plan, project: Project) throws {
        let version = try? Checker.check(project: project, version: options.appVersion)
            .versionString
        let outcome = try DeviceClassAdoption.adopt(
            DeviceClassAdoption.unlisted(in: plan), version: version, in: project
        )

        guard outcome.added.isEmpty == false else { return }
        print("Added \(outcome.added.joined(separator: ", ")) to this project.")
        if version == nil {
            print("There is no version folder yet, so no screenshot folders were made.")
        }
        print("")
    }

    /// Says how to take in a device class the waiting files name, for somebody
    /// reading a refusal that names one.
    private func offerTheDeviceClasses(_ plan: Inbox.Plan) {
        let unlisted = DeviceClassAdoption.unlisted(in: plan)
        guard unlisted.isEmpty == false else { return }

        let names = unlisted.map(\.id).joined(separator: ", ")
        print("")
        print("Run it again with --adopt-devices to add \(names) to this project.")
    }

    private func fileEverything(_ plan: Inbox.Plan, project: Project) async throws {
        // The same version the rest of the tool works on, so a screenshot and
        // the text beside it cannot land in two different version folders.
        guard let version = try Checker.check(project: project, version: options.appVersion)
            .versionString
        else {
            print("")
            print("This project has no version folder yet, so there is nowhere to file these.")
            throw ExitCode.failure
        }

        let outcome: Inbox.Outcome
        do {
            outcome = try await Inbox.file(plan, version: version, listing: readListing(project), in: project)
        } catch let lock as ScreenshotLock {
            print("")
            print(lock.description)
            print("Nothing has moved.")
            throw ExitCode.failure
        }
        let locales = outcome.locales.joined(separator: ", ")

        print("")
        if outcome.filed > 0 {
            print("Filed \(countedNoun(outcome.filed, "screenshot")) into \(locales), "
                + "version \(version).")
        }
        for arrival in outcome.creative {
            print("Filed \(arrival.file.fileName) as the \(arrival.locale) \(arrival.role.rawValue), "
                + "version \(version).")
        }
        print("The inbox copies are in the Trash.")

        // copiesScreenshotsFrom made these with nothing asked, so each is named.
        for copy in outcome.copied {
            print("\(copy.locale)/\(copy.deviceClass.id) now holds the \(copy.from) "
                + "screenshots: \(copy.count) of them.")
        }
        if outcome.copied.contains(where: { $0.trashed > 0 }) {
            print("The files that were there are in the Trash.")
        }
    }

    /// What App Store Connect says about the version, so a version it locked
    /// is refused. Nil when it cannot be read: filing then goes ahead, as it
    /// does in the window with no connection, and the push refuses later.
    private func readListing(_ project: Project) async -> RemoteListing? {
        do {
            return try await makeClient(for: project).listing(
                bundleID: project.config.bundleID,
                platform: project.config.resolvedPlatform,
                includeScreenshots: false
            )
        } catch {
            print("warning: could not read App Store Connect, so the version state is not checked. \(error)")
            return nil
        }
    }
}
