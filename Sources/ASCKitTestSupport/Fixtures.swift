import ASCKitAPI
import Foundation

// MARK: - Folders

/// Where tests make their folders. Inside the package's own `.build`, so a
/// failed test leaves files to look at, and git already ignores them.
public enum TestFolders {
    /// Made once, by `static let`, so parallel tests never race to make it.
    public static let root: URL = {
        // #filePath is .../Sources/ASCKitTestSupport/Fixtures.swift
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appending(path: ".build")
            .appending(path: "test-fixtures")
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    /// A new empty folder with a name no other test can have.
    public static func make(prefix: String) throws -> URL {
        let url = root.appending(path: "\(prefix)-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        return url
    }
}

// MARK: - A listing to start from

public extension RemoteListing {
    /// A listing of the shared demo app, ready for submission. A test passes only
    /// what it cares about.
    static func fixture(
        appInfoID: String? = "info1",
        appInfoState: AppInfoState? = .prepareForSubmission,
        versionID: String = "v1",
        versionString: String = "1.0",
        versionState: AppVersionState? = .prepareForSubmission,
        releasedVersionString: String? = nil,
        pendingVersionString: String? = nil,
        appInfoLocalizations: [String: RemoteLocalization] = [:],
        versionLocalizations: [String: RemoteLocalization] = [:],
        screenshotSets: [RemoteScreenshotSet] = [],
        placements: [RemotePlacement] = [],
        live: LiveTexts? = nil
    ) -> RemoteListing {
        RemoteListing(
            appID: "app1",
            appName: "Demo",
            bundleID: "com.example.Demo",
            appInfoID: appInfoID,
            appInfoState: appInfoState,
            versionID: versionID,
            versionString: versionString,
            versionState: versionState,
            releasedVersionString: releasedVersionString,
            pendingVersionString: pendingVersionString,
            appInfoLocalizations: appInfoLocalizations,
            versionLocalizations: versionLocalizations,
            screenshotSets: screenshotSets,
            placements: placements,
            live: live
        )
    }
}
