import ArgumentParser
import ASCKitAPI
import ASCKitProject
import Foundation

/// The version App Store Connect is on, held against the folders on disk, in
/// the same words for every command that needs to say it.
enum VersionCheck {
    /// Prints the drift and hands it back. Prints nothing when the two agree.
    @discardableResult
    static func report(listing: RemoteListing, project: Project) throws -> VersionDrift.Outcome {
        let drift = try VersionDrift.compare(listing: listing, project: project)
        if let problem = drift.problem(versionsPath: project.config.versionsPath) {
            print("")
            print(ProblemFormatter.line(for: problem, rootURL: project.rootURL))
        }
        return drift
    }

    /// What a push would change, or a stop when App Store Connect has moved to
    /// a version this project has no folder for.
    ///
    /// Every command that reaches App Store Connect works on the folder named
    /// after the version it read back. Without this the run ends in
    /// `noSuchVersion`, which names a folder and says nothing about the app
    /// having moved to a new version.
    static func plan(in reading: PushSession.Reading, project: Project) throws -> ChangePlan {
        if let problem = reading.drift.problem(versionsPath: project.config.versionsPath) {
            print("")
            print(ProblemFormatter.line(for: problem, rootURL: project.rootURL))
        }

        guard let changes = reading.changes else {
            print("Run asckit pull --create-version to make it. Nothing was written.")
            throw ExitCode.failure
        }
        return changes
    }
}
