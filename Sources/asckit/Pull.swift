import ArgumentParser
import ASCKitAPI
import ASCKitProject
import Foundation

struct Pull: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "pull",
        abstract: "Read what App Store Connect currently holds for this app.",
        discussion: """
        This is the first command that needs a key, so it is also the one that \
        proves the key works. It reads and writes nothing on App Store Connect.

        The locale list it prints is authoritative. App Store Connect skips a \
        locale code it does not recognise instead of refusing it, so a code \
        taken from anywhere else can look right and upload nothing.

        With --write it turns the listing into app information files, which is how to start \
        a project from an app that already has a listing. It never overwrites an \
        existing file unless --force is given.

        It also says when App Store Connect has moved to a version this project \
        has no folder for, which is what stops a diff or a push. \
        --create-version makes that folder and fills it with what App Store \
        Connect copied into that version: the app information of every listed \
        language, and the screenshots an older version folder holds by checksum.

        --adopt-locales takes every language App Store Connect holds and this \
        project does not list into the project: the locale list, an app \
        information file per language, and the folders their screenshots go in. \
        It writes over nothing.

        It also names a version folder for a version App Store Connect never \
        released: one newer than the version on sale and older than the \
        version after it. That happens when a version gets a new number \
        before release. --prune-versions moves those folders to the Trash.
        """
    )

    @OptionGroup var options: ProjectOptions

    @Flag(name: .long, help: "Write a app information file for every language of the listing.")
    var write = false

    @Flag(name: .long, help: "Overwrite app information files that are already there.")
    var force = false

    @Flag(
        name: .long,
        help: "Make the folder for the version App Store Connect is on, when there is none, and fill it."
    )
    var createVersion = false

    @Flag(
        name: .long,
        help: "Take every language App Store Connect holds into the project, files and folders and all."
    )
    var adoptLocales = false

    @Flag(
        name: .long,
        help: "Move the folders of versions App Store Connect never released to the Trash."
    )
    var pruneVersions = false

    @Flag(name: .long, help: "Skip reading screenshots, which is the slow part.")
    var noScreenshots = false

    @Flag(name: .long, help: "Read the in-app purchases as well. With --write, put them in files.")
    var products = false

    func run() async throws {
        let project = try options.loadProject()
        let client = try makeClient(for: project)
        let listing = try await client.listing(
            bundleID: project.config.bundleID,
            versionString: options.appVersion,
            platform: project.config.resolvedPlatform,
            // The new folder takes its screenshots by checksum, so it needs them.
            includeScreenshots: noScreenshots == false || createVersion
        )

        report(listing, project: project)

        let drift = try VersionCheck.report(listing: listing, project: project)
        if createVersion {
            try makeVersionFolder(drift, listing: listing, project: project)
        }
        try pruneUnreleased(listing: listing, project: project)

        if write {
            let outcome = try SnapshotWriter.write(
                listing: listing,
                to: project,
                version: listing.versionString,
                overwrite: force
            )
            reportWrite(outcome, project: project, version: listing.versionString)
        }

        if adoptLocales {
            try adopt(listing, project: project, drift: drift)
        }

        if products {
            try await readProducts(client: client, project: project)
            try await reportTerritories(client: client)
        }
    }

    // MARK: - Territories

    /// The territory table gives every price its currency, so a table App
    /// Store Connect has moved past shows a wrong symbol.
    private func reportTerritories(client: ASCClient) async throws {
        let remote = try await client.territories()
        let drift = TerritoryDrift.compare(
            remote: Dictionary(uniqueKeysWithValues: remote.map { ($0.id, $0.attributes?.currency) })
        )
        guard drift.agrees == false else { return }

        print("")
        print("ASCKit's territory table is out of date. Tell the ASCKit developers:")
        if drift.missingHere.isEmpty == false {
            print("  Not in the table: \(drift.missingHere.joined(separator: ", "))")
        }
        if drift.missingThere.isEmpty == false {
            print("  Not on App Store Connect: \(drift.missingThere.joined(separator: ", "))")
        }
        for change in drift.currencies {
            print("  \(change.territory) bills in \(change.appStoreConnect ?? "no currency"), "
                + "the table says \(change.table)")
        }
    }

    // MARK: - In-app purchases

    /// What the store holds for a product's words, and whether a push can
    /// write them.
    private static func versionLine(_ version: RemoteProductVersion?) -> String {
        guard let version else { return "none, so a push needs one made first" }

        let state = (version.state?.rawValue ?? unknownState)
            .lowercased().replacingOccurrences(of: "_", with: " ")
        let number = version.number.map { "\($0)" } ?? "?"
        if version.needsNewDraft {
            return "\(number), \(state), so a push makes a new draft"
        }
        guard version.acceptsChanges else {
            return "\(number), \(state), so a push waits for it"
        }
        return "\(number), \(state)"
    }

    /// A product is not tied to a version, so this runs whatever the version
    /// drift said.
    private func readProducts(client: ASCClient, project: Project) async throws {
        let remote = try await client.products(bundleID: project.config.bundleID)
        print("")

        guard remote.products.isEmpty == false else {
            print("App Store Connect holds no in-app purchases for this app.")
            return
        }

        print("In-app purchases on App Store Connect: \(remote.products.count)")
        let onDisk = ProductStore.load(in: project).products
        for product in remote.products {
            let here = onDisk[product.productID] == nil ? "no file yet" : "in files"
            let words = product.localizations.keys.sorted().joined(separator: ", ")
            print("  \(product.productID)  \(product.kind)  \(here)")
            print("    \(product.state ?? unknownState), words in: \(words.isEmpty ? "none" : words)")
            // Whether the push writes into a draft, makes one, or waits is
            // worth seeing before the push.
            print("    words version: \(Self.versionLine(product.version))")
        }

        let unshipped = ProductSnapshot.unshippedLocales(in: remote, config: project.config)
        if unshipped.isEmpty == false {
            print("")
            print("Languages the store holds for these that this project does not list: "
                + unshipped.joined(separator: ", "))
        }

        let drift = SubscriptionGroupDrift.compare(local: ProductStore.load(in: project), remote: remote)
        if drift.agrees == false, write == false {
            print("")
            print("App Store Connect renamed or removed a subscription group: "
                + (drift.renames.map(\.from) + drift.gone).joined(separator: ", "))
        }

        guard write else {
            print("")
            print("Run pull --products --write to put these in \(project.config.productsPath)/.")
            return
        }

        // Before the snapshot, which would write the new name beside the old.
        if drift.agrees == false {
            let followed = try SubscriptionGroupDrift.follow(drift, from: remote, in: project)
            print("")
            print(PushOutcomeText.describe(followed))
        }

        // The lists come from the package, so this and the window say the same
        // thing. What follows each one is advice, and advice belongs to the
        // terminal: there is no --force in a window.
        let outcome = try ProductSnapshot.write(remote, to: project, overwrite: force)
        print("")
        print(PushOutcomeText.describe(outcome))

        if outcome.written.isEmpty == false {
            print("")
            print("Each one is needs_human and has no price plan. "
                + "Run asckit price to give one a price.")
        }
        if outcome.left.isEmpty == false, force == false {
            print("")
            print("Use --force to overwrite them.")
        }
    }

    /// Takes the languages App Store Connect holds into the project.
    ///
    /// The rule for what can be taken in lives in the package, so this command
    /// and the app's sidebar refuse the same states for the same reasons and
    /// write the same files.
    private func adopt(_ listing: RemoteListing, project: Project, drift: VersionDrift.Outcome) throws {
        print("")

        let plan: LocaleAdoption.Plan
        switch LocaleAdoption.plan(
            locales: LocaleDrift.compare(listing: listing, config: project.config),
            versions: drift,
            config: project.config
        ) {
        case let .success(ready):
            plan = ready
        case let .failure(refusal):
            print("\(refusal)")
            if case .noFolderForVersion = refusal {
                print("Run asckit pull --create-version to make it. Nothing was written.")
                throw ExitCode.failure
            }
            return
        }

        let outcome = try LocaleAdoption.adopt(plan, listing: listing, in: project)
        print("Added to the locale list: \(outcome.added.joined(separator: ", "))")

        if outcome.written.isEmpty == false {
            let name = project.informationURL(version: outcome.version).lastPathComponent
            let folder = "\(project.config.versionsPath)/\(outcome.version)/\(name)"
            print("Wrote an app information file in \(folder) for: "
                + "\(outcome.written.joined(separator: ", "))")
        }
        if outcome.left.isEmpty == false {
            print("Left alone, already there: \(outcome.left.joined(separator: ", "))")
        }
    }

    /// Names the folders without `--prune-versions`, and moves them with it.
    /// The rule is in `UnreleasedVersions`, which the app uses as well.
    private func pruneUnreleased(listing: RemoteListing, project: Project) throws {
        let versionsPath = project.config.versionsPath
        let names = try UnreleasedVersions.folders(listing: listing, project: project)
        guard names.isEmpty == false else { return }

        print("")
        guard pruneVersions else {
            let paths = names.map { "\(versionsPath)/\($0)" }.joined(separator: ", ")
            print("App Store Connect never released these versions: \(paths)")
            print("Run asckit pull --prune-versions to move their folders to the Trash.")
            return
        }

        let trashed = try UnreleasedVersions.moveToTrash(listing: listing, in: project)
        print(PushOutcomeText.describeTrashedVersions(trashed, versionsPath: versionsPath))
    }

    /// The work is in `VersionSeed`, which the app uses as well.
    private func makeVersionFolder(
        _ drift: VersionDrift.Outcome,
        listing: RemoteListing,
        project: Project
    ) throws {
        guard let version = drift.versionToCreate else {
            print("There is already a folder for version \(drift.version).")
            return
        }

        let outcome = try VersionSeed.seed(version: version, from: listing, in: project)
        print(PushOutcomeText.describe(outcome, versionsPath: project.config.versionsPath))
    }

    private func report(_ listing: RemoteListing, project: Project) {
        print("\(listing.appName ?? listing.bundleID) (\(listing.bundleID))")
        print("Version \(listing.versionString), \(listing.versionState?.rawValue ?? unknownState)")

        if listing.canEditText == false {
            print("This version does not accept text changes.")
        }
        if listing.canEditNameAndSubtitle == false {
            print("The name and the subtitle cannot be changed until a new version is editable.")
        }

        print("")
        print("Languages App Store Connect holds (\(listing.locales.count)):")
        for locale in listing.locales {
            print("  \(locale)\(unknownMarker(locale))\(screenshotSummary(locale, in: listing))")
        }

        let missing = project.config.locales.filter { listing.locales.contains($0) == false }
        if missing.isEmpty == false {
            print("")
            print("In the configuration but not on App Store Connect: \(missing.joined(separator: ", "))")
            print("A push creates them.")
        }
    }

    /// A locale ASCKit does not know is worth flagging here, because this list
    /// is the authoritative one and the table may simply be out of date.
    private func unknownMarker(_ locale: String) -> String {
        StoreLocale.isKnown(locale) ? "" : "  (not in ASCKit's locale table)"
    }

    /// Each placement group of the language with how many assets it shows,
    /// such as `IPHONE_DUO_PROFILE 6`.
    private func screenshotSummary(_ locale: String, in listing: RemoteListing) -> String {
        let slots = LibraryReport.slots(of: listing.placements.filter { $0.locale == locale })
        guard slots.isEmpty == false else { return "" }
        let described = slots.map { "\($0.group) \($0.placements.count)" }
        return "  [\(described.joined(separator: ", "))]"
    }

    private func reportWrite(_ outcome: SnapshotWriter.Outcome, project: Project, version: String) {
        print("")
        if outcome.written.isEmpty == false {
            let name = project.informationURL(version: version).lastPathComponent
            let folder = "\(project.config.versionsPath)/\(version)/\(name)"
            let counted = countedNoun(outcome.written.count, "app information file")
            print("Wrote \(counted) to \(folder): "
                + outcome.written.joined(separator: ", "))
        }
        if outcome.skipped.isEmpty == false {
            print("Left alone, already there: \(outcome.skipped.joined(separator: ", "))")
            print("Use --force to overwrite them.")
        }
    }
}
