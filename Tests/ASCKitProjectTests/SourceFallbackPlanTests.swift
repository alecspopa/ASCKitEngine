import ASCKitAPI
import Foundation
import Testing
@testable import ASCKitProject

/// A language set to show the source language's screenshots or art has none
/// of its own on App Store Connect, so App Store Connect falls back to the
/// source language. The push uploads nothing for it and places nothing on it.
struct SourceFallbackPlanTests {
    let fixture: FixtureProject
    let deviceClass = DeviceClass.iPhone69

    init() throws {
        fixture = try FixtureProject()
    }

    func listing(placements: [RemotePlacement]) -> RemoteListing {
        RemoteListing(
            appID: "app1", appName: "Demo", bundleID: "com.example.MyApp",
            appInfoID: "info1", appInfoState: .prepareForSubmission,
            versionID: "v1", versionString: "1.0", versionState: .prepareForSubmission,
            appInfoLocalizations: [:],
            versionLocalizations: [
                "en-US": RemoteLocalization(id: "l-us", locale: "en-US", values: [:]),
                "en-GB": RemoteLocalization(id: "l-gb", locale: "en-GB", values: [:])
            ],
            screenshotSets: [],
            placements: placements
        )
    }

    /// en-US has a screenshot and a header. en-GB has nothing, and shows en-US's.
    func content() throws -> VersionContent {
        try fixture.writeConfig(ProjectConfig(
            bundleID: "com.example.MyApp", keyID: "ABC123", issuerID: "issuer",
            locales: ["en-US", "en-GB"], deviceClasses: [deviceClass.id],
            usesSourceScreenshots: ["en-GB": [deviceClass.id]],
            usesSourceCreative: ["en-GB"]
        ))
        for locale in ["en-US", "en-GB"] {
            try fixture.writeCopy(AppInformation(locale: locale, status: .approved, fields: AppInformation.Fields(
                name: "Stocked", subtitle: "Pantry", keywords: "pantry", description: "Words.",
                whatsNew: "New.", supportUrl: "https://example.com/support",
                privacyPolicyUrl: "https://example.com/privacy"
            )))
        }
        try fixture.writeScreenshot(locale: "en-US", deviceClassID: deviceClass.id,
                                    named: "01-a.png", width: 1320, height: 2868)

        let creative = fixture.rootURL.appending(path: "versions/1.0/creative/en-US")
        try FileManager.default.createDirectory(at: creative, withIntermediateDirectories: true)
        try PNGWriter.write(to: creative.appending(path: "header.png"), width: 5244, height: 2950, hasAlpha: false)

        return try fixture.content()
    }

    func placed(_ id: String, type: PlacementType, group: String) -> RemotePlacement {
        RemotePlacement(id: id, locale: "en-GB", type: type, group: group, state: .parentPrepareForSubmission,
                        asset: RemoteLibraryAsset(id: "asset-\(id)", media: .image, state: .approved))
    }

    @Test func uploadsNothingForALanguageThatShowsTheSource() throws {
        defer { fixture.remove() }
        let listing = listing(placements: [])
        let plan = try Planner.plan(local: content(), config: fixture.load().config, remote: listing,
                                    record: AssetRecord())

        let targets = PushSession.targets(in: plan, listing: listing)
        #expect(targets.allSatisfy { $0.label == "en-US" })
        #expect(Set(targets.map(\.parent)) == [.versionLocalization(id: "l-us")])
        #expect(LibraryPusher.uploads(in: targets).count == 2, "the en-US screenshot and header, once each")
    }

    @Test func takesOffWhatALanguageThatShowsTheSourceHolds() throws {
        defer { fixture.remove() }
        let listing = listing(placements: [
            placed("shot", type: deviceClass.screenshotPlacementType, group: deviceClass.placementGroup),
            placed("header", type: .productPageHeader, group: CreativeRole.group),
            placed("search", type: .searchResults, group: CreativeRole.group)
        ])
        let plan = try Planner.plan(local: content(), config: fixture.load().config, remote: listing,
                                    record: AssetRecord())

        let british = PushSession.targets(in: plan, listing: listing).filter { $0.label == "en-GB" }
        #expect(british.count == 3)
        #expect(british.allSatisfy { $0.files.isEmpty })
        #expect(british.allSatisfy { LibraryPlanner.action(for: $0.slot) == .replace(removing: 1, adding: 0) })
    }
}
