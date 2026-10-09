import ASCKitAPI
import ASCKitTestSupport
import Foundation
import Testing
@testable import ASCKitProject

/// Moondane had 1.15 on sale and 1.16 pending. Then 1.16 became 2.0 in App
/// Store Connect, and the folder for 1.16 stayed with nothing behind it.
final class UnreleasedVersionsTests {
    let fixture: FixtureProject

    init() throws {
        fixture = try FixtureProject()
        try fixture.writeConfig(ProjectConfig(
            bundleID: "com.example.Demo",
            keyID: "ABC123",
            issuerID: "issuer",
            sourceLocale: "en-US",
            locales: ["en-US"],
            deviceClasses: [DeviceClass.iPhone69.id]
        ))
    }

    deinit {
        fixture.remove()
    }

    func listing(released: String?, pending: String?) -> RemoteListing {
        .fixture(
            versionString: pending ?? released ?? "",
            versionState: pending == nil ? .readyForDistribution : .prepareForSubmission,
            releasedVersionString: released,
            pendingVersionString: pending
        )
    }

    @Test func namesAFolderBetweenTheReleaseAndThePendingVersion() {
        let names = UnreleasedVersions.folders(
            listing: listing(released: "1.15", pending: "2.0"),
            versions: ["1.14", "1.15", "1.16", "2.0"]
        )

        #expect(names == ["1.16"])
    }

    /// 1.10 is newer than 1.9, the way version numbers read.
    @Test func comparesVersionNumbersTheWayTheyRead() {
        let names = UnreleasedVersions.folders(
            listing: listing(released: "1.9", pending: "1.11"),
            versions: ["1.8", "1.9", "1.10", "1.11"]
        )

        #expect(names == ["1.10"])
    }

    /// A folder newer than the pending version is a release somebody plans.
    @Test func keepsAFolderNewerThanThePendingVersion() {
        let names = UnreleasedVersions.folders(
            listing: listing(released: "1.15", pending: "2.0"),
            versions: ["1.15", "2.0", "2.1"]
        )

        #expect(names.isEmpty)
    }

    /// With nothing pending, a folder after the release is the next release.
    @Test func keepsEverythingWhenNothingIsPending() {
        let names = UnreleasedVersions.folders(
            listing: listing(released: "1.15", pending: nil),
            versions: ["1.15", "1.16"]
        )

        #expect(names.isEmpty)
    }

    /// Before the first release, every folder older than the pending version
    /// is a number the app dropped.
    @Test func namesOlderFoldersBeforeTheFirstRelease() {
        let names = UnreleasedVersions.folders(
            listing: listing(released: nil, pending: "1.1"),
            versions: ["1.0", "1.1"]
        )

        #expect(names == ["1.0"])
    }

    @Test func movesOnlyTheUnreleasedFolderToTheTrash() throws {
        let project = try fixture.load()
        for version in ["1.15", "1.16", "2.0"] {
            try ContentWriter.createVersion(version, in: project)
        }

        let trashed = try UnreleasedVersions.moveToTrash(
            listing: listing(released: "1.15", pending: "2.0"),
            in: project
        )

        #expect(trashed == ["1.16"])
        #expect(try project.versionNames() == ["1.15", "2.0"])
    }

    @Test func namesTheTrashedFoldersByThePathTheProjectUses() {
        let text = PushOutcomeText.describeTrashedVersions(["1.16"], versionsPath: "versions")

        #expect(text.contains("never released"))
        #expect(text.contains("  versions/1.16"))
        #expect(PushOutcomeText.describeTrashedVersions([], versionsPath: "versions").isEmpty)
    }
}
