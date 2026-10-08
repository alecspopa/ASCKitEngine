import ASCKitAPI
import Foundation
import Testing
@testable import ASCKitProject

/// The digest is what tells a push that the plan somebody read is still the
/// plan. It has to move whenever anything a push would write moves, including
/// the part of a value that is too long to be shown.
final class ChangePlanDigestTests {
    let fixture: FixtureProject

    init() throws {
        fixture = try FixtureProject()
    }

    deinit {
        fixture.remove()
    }

    // MARK: - Building the two sides

    func config() -> ProjectConfig {
        ProjectConfig(
            bundleID: "com.example.Demo",
            keyID: "ABC123",
            issuerID: "issuer",
            sourceLocale: "en-US",
            locales: ["en-US"],
            deviceClasses: []
        )
    }

    func listing(
        versionString: String = "1.0",
        versionState: AppVersionState = .prepareForSubmission,
        version: [String: [String: String]] = [:]
    ) -> RemoteListing {
        // ASCKit writes into a page App Store Connect already holds and never
        // makes one, so en-US is always there, empty until a test fills it.
        var version = version
        version["en-US"] = version["en-US"] ?? [:]

        return RemoteListing(
            appID: "app1",
            appName: "Demo",
            bundleID: "com.example.Demo",
            appInfoID: "info1",
            appInfoState: .prepareForSubmission,
            versionID: "v1",
            versionString: versionString,
            versionState: versionState,
            appInfoLocalizations: [:],
            versionLocalizations: version.mapValues {
                RemoteLocalization(id: "v-\($0.hashValue)", locale: "en-US", values: $0)
            },
            screenshotSets: []
        )
    }

    func plan(description: String, remote: RemoteListing) throws -> ChangePlan {
        try fixture.writeConfig(config())
        try fixture.writeCopy(AppInformation(
            locale: "en-US",
            status: .approved,
            fields: AppInformation.Fields(description: description)
        ))
        let local = try ContentStore.load(version: fixture.version, in: fixture.load())
        return Planner.plan(local: local, config: config(), remote: remote)
    }

    // MARK: - Tests

    @Test func givesTheSameAnswerForThePlanReadTwice() throws {
        let first = try plan(description: "Know what you have.", remote: listing())
        let second = try plan(description: "Know what you have.", remote: listing())

        #expect(first.digest == second.digest)
    }

    /// The formatter shortens a long value to 72 characters, so two plans that
    /// differ only past that point print the same lines. The digest is the only
    /// thing standing between that and a push writing the wrong words.
    @Test func movesWhenAValueDiffersPastWhereTheLineIsCut() throws {
        let shared = String(repeating: "a", count: 200)
        let first = try plan(description: "\(shared)one", remote: listing())
        let second = try plan(description: "\(shared)two", remote: listing())

        #expect(ChangePlanFormatter.lines(for: first) == ChangePlanFormatter.lines(for: second))
        #expect(first.digest != second.digest)
    }

    @Test func movesWhenAppStoreConnectHoldsSomethingDifferent() throws {
        let text = "Know what you have."
        let first = try plan(description: text, remote: listing())
        let second = try plan(
            description: text,
            remote: listing(version: ["en-US": ["description": "Something older"]])
        )

        #expect(first.digest != second.digest)
    }

    @Test func movesWhenTheVersionStateChanges() throws {
        let text = "Know what you have."
        let first = try plan(description: text, remote: listing())
        let second = try plan(description: text, remote: listing(versionState: .waitingForReview))

        #expect(first.digest != second.digest)
    }

    @Test func movesWhenAppStoreConnectOpensADifferentVersion() throws {
        let text = "Know what you have."
        let first = try plan(description: text, remote: listing())
        let second = try plan(description: text, remote: listing(versionString: "1.1"))

        #expect(first.digest != second.digest)
    }
}
