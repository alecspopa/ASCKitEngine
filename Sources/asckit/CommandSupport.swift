import ASCKitAPI
import ASCKitProject
import Foundation

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
