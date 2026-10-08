import ArgumentParser
import ASCKitProject
import Foundation

/// Reading which language got the newer screenshots, and copying them into the
/// language beside it.
///
/// All of it goes through `SiblingScreenshots` in the package, which is what the
/// app copies through as well, so a copy the window refuses is refused in the
/// terminal for the same stated reason.
struct CopyScreenshots: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "copy-screenshots",
        abstract: "Copy the newer screenshots into the language beside them.",
        discussion: """
        With no flag it reads what could be copied and writes nothing.

        `es-ES` and `es-MX` read the same pictures, so a new export that landed in one of them \
        belongs in the other. This finds the language holding the older set and offers the \
        newer one next door.

        Only inside one language. The `en-US` screenshots are English pictures, and copying \
        them into `es-ES` would publish a Spanish listing with English artwork. App Store \
        Connect already shows them wherever a language has none, and saying that on purpose is \
        what usesSourceScreenshots is for.

        A copy makes the two folders match. Whatever the older language held goes to the Trash, \
        so nothing is left half old and half new.

        A copy is written into copiesScreenshotsFrom in asckit.json. It holds for every version, \
        so asckit pull --create-version makes the same copy in the new folder.
        """
    )

    @OptionGroup var options: ProjectOptions

    @Flag(name: .long, help: "Make every copy in the list.")
    var all = false

    @Option(
        name: .long,
        help: ArgumentHelp(
            "Make one copy, by the number the list gives it.",
            valueName: "number"
        )
    )
    var accept: Int?

    func run() throws {
        let project = try options.loadProject()
        let result = try Checker.check(project: project, version: options.appVersion)

        guard let version = result.versionString else {
            print("This project has no versions yet, so there is nothing to copy.")
            throw ExitCode.failure
        }

        let content = try ContentStore.load(version: version, in: project)
        let offers = SiblingScreenshots.offers(in: content, config: project.config)

        guard all == false || accept == nil else {
            print("Pass one of --all and --accept.")
            throw ExitCode.failure
        }

        guard offers.isEmpty == false else {
            print("Every language holds the same screenshots as the language beside it.")
            return
        }

        if all {
            try copy(offers, version: version, in: project)
        } else if let accept {
            try copyOne(numbered: accept, from: offers, version: version, in: project)
        } else {
            list(offers, version: version)
        }
    }

    // MARK: - Reading

    private func list(_ offers: [SiblingScreenshots.Offer], version: String) {
        print("Screenshots worth copying in \(version):")
        for (index, offer) in offers.enumerated() {
            print("  \(index + 1)  \(offer.locale) <- \(offer.from)  \(offer.deviceClassID)")
            print("     \(offer.summary)")
        }

        print("")
        print("Make one with asckit copy-screenshots --accept <number>, or all of them with --all.")
    }

    // MARK: - Writing

    private func copyOne(
        numbered number: Int,
        from offers: [SiblingScreenshots.Offer],
        version: String,
        in project: Project
    ) throws {
        guard number >= 1, number <= offers.count else {
            print("There is no \(number) in the list. Run asckit copy-screenshots to read it.")
            throw ExitCode.failure
        }
        try copy([offers[number - 1]], version: version, in: project)
    }

    /// Every copy is tried, so one language that cannot take its set does not
    /// hold up the rest. The exit code still says something went wrong.
    private func copy(
        _ offers: [SiblingScreenshots.Offer],
        version: String,
        in project: Project
    ) throws {
        var refused = false

        for offer in offers {
            do {
                let files = try SiblingScreenshots.accept(offer, version: version, in: project)
                print("\(offer.locale)/\(offer.deviceClassID) now holds the \(offer.from) "
                    + "screenshots: \(files.count) of them.")
            } catch {
                refused = true
                print("\(offer.locale)/\(offer.deviceClassID): \(error)")
            }
        }

        print("")
        print("The files that were there are in the Trash.")
        if refused { throw ExitCode.failure }
    }
}
