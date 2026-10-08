import ArgumentParser
import ASCKitAPI
import ASCKitProject
import Foundation

struct Diff: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "diff",
        abstract: "Show what a push would change on App Store Connect.",
        discussion: """
        Reads both sides and compares them. It writes nothing, on App Store \
        Connect or on disk.

        Screenshots are compared by name, size and checksum, because App Store \
        Connect cannot change one image in place: any difference means removing \
        the whole set and uploading it again. A set that already matches is left \
        alone.

        Exits non-zero when there is something to change, so it can be used to \
        ask whether a push is needed.
        """
    )

    @OptionGroup var options: ProjectOptions

    @Flag(name: .long, help: "Check the files first, and stop if anything is wrong.")
    var check = false

    @Flag(
        name: .long,
        help: "Read what every in-app purchase costs, and show every country rather than the first few."
    )
    var prices = false

    func run() async throws {
        let project = try options.loadProject()

        if check {
            let result = try Checker.check(project: project, version: options.appVersion)
            guard result.errors.isEmpty else {
                for problem in result.errors {
                    print(ProblemFormatter.line(for: problem, rootURL: project.rootURL))
                }
                print("")
                print(ProblemFormatter.summary(result.problems))
                throw ExitCode.failure
            }
        }

        let client = try ASCClient(key: PrivateKeyStore.apiKey(for: project.config))
        let session = PushSession(project: project, client: client)
        // Reading a price means reading every price the store will sell each
        // product at, which is thousands of rows per product. So it happens
        // when somebody asks to see one.
        let reading = try await session.read(
            version: options.appVersion,
            // Always App Store Connect, never the kept copy. This is the
            // command a person runs to read the ladder again, so answering it
            // off a disk would make that advice a loop with no end.
            prices: prices ? .fresh : .notRead
        )
        let listing = reading.listing
        let plan = try VersionCheck.plan(in: reading, project: project)

        print("\(listing.appName ?? listing.bundleID), version \(plan.versionString), "
            + "\(plan.versionState?.rawValue ?? "state unknown")")
        print("")

        for line in ChangePlanFormatter.lines(for: plan, showingEveryPrice: prices) {
            print(line)
        }

        for problem in reading.priceProblems {
            print(ProblemFormatter.line(for: problem, rootURL: project.rootURL))
        }

        if prices == false, plan.pricePlans.isEmpty, hasPricePlans(in: reading) {
            print("Prices are not read unless you ask. Run asckit diff --prices to see them.")
            print("")
        }

        print(ChangePlanFormatter.summary(plan))

        if plan.isEmpty == false {
            throw ExitCode.failure
        }
    }

    /// Whether any product on disk asks for a price at all, so the run can say
    /// that prices were left unread rather than saying nothing.
    private func hasPricePlans(in reading: PushSession.Reading) -> Bool {
        reading.products?.sorted.contains { $0.price != nil } ?? false
    }
}
