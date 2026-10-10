import ArgumentParser
import ASCKitAPI
import ASCKitProject
import Foundation

struct Library: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "library",
        abstract: "Show or tidy the app's asset library.",
        subcommands: [LibraryShow.self, LibraryPrune.self],
        defaultSubcommand: LibraryShow.self
    )
}

struct LibraryShow: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "show",
        abstract: "Show the app's asset library and what is placed on each language.",
        discussion: """
        Reads App Store Connect and writes nothing to it. It shows each image and video in \
        the library, and for each language of the version and of each draft test, the old \
        screenshot sets next to the placements. It keeps App Store Connect's sizes in the \
        project's cache, for asckit check.
        """
    )

    @OptionGroup var options: ProjectOptions

    @Flag(help: "Also show the placement groups App Store Connect knows.")
    var groups = false

    func run() async throws {
        let project = try options.loadProject()
        let client = try makeClient(for: project)

        let listing = try await client.listing(
            bundleID: project.config.bundleID,
            versionString: options.appVersion,
            platform: project.config.resolvedPlatform
        )
        async let experiments = client.experiments(
            bundleID: project.config.bundleID
        )
        async let customPages = client.customPages(bundleID: project.config.bundleID)
        let library = try await client.readAssetLibrary(appID: listing.appID)

        for line in try await LibraryReport.lines(
            library: library, listing: listing, experiments: experiments, customPages: customPages
        ) {
            print(line)
        }

        // Kept, so that asckit check uses App Store Connect's own sizes.
        let refData = try await client.assetLibraryRefData()
        try? RefDataCache.save(refData, in: project)

        if groups {
            print("")
            for line in LibraryReport.referenceLines(refData) {
                print(line)
            }
        }
    }
}

struct LibraryPrune: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "prune",
        abstract: "Delete the library's images and videos that nothing places.",
        discussion: """
        Only an asset in Prepare for Submission that no version, test or event places. \
        App Store Connect keeps an approved asset, which only the website can archive. \
        Without --yes this lists what it would delete and deletes nothing.
        """
    )

    @OptionGroup var options: ProjectOptions

    @Flag(name: .long, help: "Delete them.")
    var yes = false

    func run() async throws {
        let project = try options.loadProject()
        let client = try makeClient(for: project)
        guard let app = try await client.app(bundleID: project.config.bundleID) else {
            throw ListingError.noSuchApp(bundleID: project.config.bundleID)
        }

        let session = PushSession(project: project, client: client)
        let read = try await session.readPrune(appID: app.id)
        guard read.library != nil else {
            print("This app has no asset library on App Store Connect.")
            return
        }
        guard read.candidates.isEmpty == false else {
            print("Nothing to delete. Every asset in Prepare for Submission is placed.")
            return
        }

        print("Assets that nothing places: \(read.candidates.count).")
        for asset in read.candidates {
            print("  \(asset.fileName ?? asset.id) (\(asset.media.rawValue.lowercased()), \(asset.id))")
        }
        guard yes else {
            print("Nothing deleted. Run again with --yes to delete them.")
            return
        }

        let result = await session.prune(read.candidates)
        print("Deleted: \(result.deleted.count).")
        for refusal in result.refused {
            print("  Not deleted: \(refusal.asset.fileName ?? refusal.asset.id). \(refusal.message)")
        }
        if result.refused.isEmpty == false { throw ExitCode.failure }
    }
}
