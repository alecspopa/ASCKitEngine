import ArgumentParser
import ASCKitAPI
import ASCKitProject
import Foundation

// MARK: - Asking before a write

/// The `--yes` flag of a push that asks first.
struct ConfirmOptions: ParsableArguments {
    @Flag(name: .long, help: "Do not ask. Use only for a plan you have already read.")
    var yes = false

    /// Asks unless `--yes` was passed. Stops the command when the answer is no.
    func require(_ question: String) throws {
        try requireConfirmation(yes: yes, question)
    }
}

/// Asks before writing. Anything but yes is no, so a stray keypress or a
/// pipe with nothing on the other end leaves App Store Connect alone.
func confirm(_ question: String) -> Bool {
    print("")
    print("\(question) [y/N] ", terminator: "")
    guard let answer = readLine()?.trimmingCharacters(in: .whitespaces).lowercased() else {
        return false
    }
    return answer == "y" || answer == "yes"
}

/// Passes when the person said yes or passed `--yes`. Says so when it is no.
func requireConfirmation(yes: Bool, _ question: String) throws {
    guard yes || confirm(question) else {
        print("Nothing written.")
        throw ExitCode.failure
    }
}

/// The plan of a reading, for a push of the in-app purchases. Stops when
/// nothing was read.
func plannedProducts(in reading: PushSession.Reading) throws -> ChangePlan {
    guard let plan = reading.changes else {
        print("Nothing was read from App Store Connect.")
        throw ExitCode.failure
    }
    return plan
}

/// What a dry run prints: how many requests would go, the first few in full,
/// and a note for the rest.
///
/// One request per product per language or country, and after the first few
/// they differ only in a few words. Printing every one buries the thing
/// somebody opened this to look at.
func printDryRun(_ bodies: [String], shown: Int, more: String, extraLines: [String] = []) {
    print("")
    print("\(countedNoun(bodies.count, "request")) would go. Nothing was sent.")

    for body in bodies.prefix(shown) {
        print("")
        print(body)
    }

    let hidden = bodies.count - shown
    if hidden > 0 {
        print("")
        print("...and \(hidden) more like it, \(more)")
        for line in extraLines {
            print(line)
        }
    }
}

/// Reports where the receipt went and fails the command when the push did not fully work.
/// The caller prints its own report first, because the words differ.
func finish(
    _ outcome: PushSession.Outcome<some Any>,
    project: Project,
    succeeded: Bool
) throws {
    reportReceipt(outcome, project: project)
    if succeeded == false { throw ExitCode.failure }
}

/// What a listing says when App Store Connect gives no state.
let unknownState = "state unknown"

/// The client for a project's key. Warns when other accounts can read the key,
/// so every command that talks to App Store Connect says it, not only `pull`.
func makeClient(for project: Project) throws -> ASCClient {
    let key = try PrivateKeyStore.apiKey(for: project.config)
    if let url = PrivateKeyStore.locate(keyID: project.config.keyID),
       PrivateKeyStore.isReadableByOthers(url: url) {
        print("warning: \(url.path) is readable by other accounts on this Mac. chmod 600 it.")
    }
    return try ASCClient(key: key)
}

func makeSession(for project: Project) throws -> PushSession {
    try PushSession(project: project, client: makeClient(for: project))
}

/// The first line of a plan: the app, its version and where the version stands.
func versionHeader(_ listing: RemoteListing, _ plan: ChangePlan) -> String {
    "\(listing.appName ?? listing.bundleID), version \(plan.versionString), "
        + "\(plan.versionState?.rawValue ?? unknownState)"
}

/// The report of an image push, the same for screenshots and for test images.
func reportImages(_ result: ScreenshotPusher.Result, readBack: String) {
    print("")
    if result.uploaded.isEmpty == false {
        print("Wrote: \(result.uploaded.joined(separator: ", "))")
    }
    for failure in result.failed {
        print("Failed, \(failure.locale) \(failure.deviceClassID): \(failure.message)")
    }
    if result.isCompleteSuccess {
        print("Done. \(readBack)")
    }
}
