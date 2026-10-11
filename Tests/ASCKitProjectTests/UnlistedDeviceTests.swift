import ASCKitAPI
import Foundation
import Testing
@testable import ASCKitProject

/// A device class the project does not list takes its images off App Store
/// Connect, in every place, and the plan says why.
struct UnlistedDeviceTests {
    let fixture: FixtureProject

    init() throws {
        fixture = try FixtureProject()
    }

    static let iPad = DeviceClass.iPad13
    static let watch = DeviceClass.watchUltra

    static let config = ProjectConfig(
        bundleID: "com.example.MyApp", keyID: "K", issuerID: "I",
        locales: ["en-US"], deviceClasses: [DeviceClass.iPhone69.id]
    )

    static func iPadPreview(_ id: String) -> RemotePlacement {
        RemotePlacement(
            id: id, locale: "en-US", type: .appPreview, group: iPad.placementGroup, state: .parentPrepareForSubmission,
            asset: RemoteLibraryAsset(id: "video-\(id)", media: .video, fileName: "\(id).mov", state: .approved)
        )
    }

    // MARK: - A version

    func listing(placements: [RemotePlacement]) -> RemoteListing {
        RemoteListing(
            appID: "app1", appName: "Demo", bundleID: "com.example.MyApp",
            appInfoID: "info1", appInfoState: .prepareForSubmission,
            versionID: "v1", versionString: "1.0", versionState: .prepareForSubmission,
            appInfoLocalizations: [:],
            versionLocalizations: ["en-US": RemoteLocalization(id: "l-en", locale: "en-US", values: [:])],
            screenshotSets: [],
            placements: placements
        )
    }

    func plan(_ listing: RemoteListing) throws -> ChangePlan {
        try fixture.writeConfig(Self.config)
        try fixture.writeCopy(AppInformation(locale: "en-US", status: .approved, fields: AppInformation.Fields(
            name: "Stocked", subtitle: "Pantry", keywords: "pantry", description: "Words.",
            whatsNew: "New.", supportUrl: "https://example.com/support",
            privacyPolicyUrl: "https://example.com/privacy"
        )))
        let project = try fixture.load()
        let local = try ContentStore.load(version: "1.0", in: project)
        return Planner.plan(local: local, config: project.config, remote: listing, record: AssetRecord())
    }

    @Test func removesTheScreenshotsOfAnUnlistedDevice() throws {
        defer { fixture.remove() }
        let listing = listing(placements: [
            Placed.placement("p1", asset: "a1", group: Self.iPad.placementGroup),
            Placed.placement("p2", asset: "a2", group: Self.iPad.placementGroup)
        ])
        let plan = try plan(listing)

        let set = try #require(plan.screenshotPlans.first { $0.deviceClass == Self.iPad })
        #expect(set.isListed == false)
        #expect(set.action == .replace(removing: 2, adding: 0))
        #expect(plan.screenshotPlans.count == 1)

        let target = try #require(PushSession.targets(in: plan, listing: listing).first)
        #expect(target.parent == .versionLocalization(id: "l-en"))
        #expect(LibraryPusher.uploads(in: [target]).isEmpty)
    }

    @Test func saysWhyTheSetGoes() throws {
        defer { fixture.remove() }
        let plan = try plan(listing(placements: [
            Placed.placement("p1", asset: "a1", group: Self.iPad.placementGroup),
            Self.iPadPreview("v1")
        ]))

        let lines = ChangePlanFormatter.lines(for: plan).filter { $0.contains("The project does not list this device.") }
        #expect(lines.count == 2)
    }

    @Test func removesThePreviewsOfAnUnlistedDevice() throws {
        defer { fixture.remove() }
        let plan = try plan(listing(placements: [Self.iPadPreview("v1")]))

        let set = try #require(plan.previewPlans.first)
        #expect(set.deviceClass == Self.iPad)
        #expect(set.isListed == false)
        #expect(set.action == .replace(removing: 1, adding: 0))
    }

    @Test func plansNothingForAnUnlistedDeviceWithNothingOnTheStore() throws {
        defer { fixture.remove() }
        let plan = try plan(listing(placements: []))

        #expect(plan.screenshotPlans.isEmpty)
        #expect(plan.previewPlans.isEmpty)
    }

    @Test func leavesAGroupThatNoDeviceClassNames() throws {
        defer { fixture.remove() }
        let plan = try plan(listing(placements: [
            Placed.placement("p1", asset: "a1", group: "IPHONE_HOME_BUTTON_35_PROFILE")
        ]))

        #expect(plan.screenshotPlans.isEmpty)
    }

    // MARK: - A test

    @Test func removesTheScreenshotsOfAnUnlistedDeviceFromATreatment() {
        defer { fixture.remove() }
        let plan = ExperimentPlanner.plan(
            local: ExperimentContent(), config: Self.config,
            remote: LibraryExperimentPlanTests.remote(placements: [
                Placed.placement("p1", asset: "a1", group: Self.iPad.placementGroup),
                Self.iPadPreview("v1")
            ]),
            record: AssetRecord()
        )

        #expect(plan.sets.map(\.deviceClass) == [Self.iPad])
        #expect(plan.sets.first?.action == .replace(removing: 1, adding: 0))
        #expect(plan.previewSets.map(\.deviceClass) == [Self.iPad])
    }

    // MARK: - A custom product page

    func pages(placements: [RemotePlacement]) -> RemoteCustomPages {
        RemoteCustomPages(
            appID: "app1",
            pages: [RemoteCustomPage(
                id: "page1", name: "Night sky", url: nil, visible: true,
                version: RemoteCustomPageVersion(
                    id: "v2", version: "2", state: .prepareForSubmission, deepLink: nil,
                    localizations: [RemoteCustomPageLocalization(
                        id: "cloc-en", locale: "en-US", promotionalText: nil, placements: placements
                    )]
                )
            )],
            keywords: [:]
        )
    }

    @Test func removesTheScreenshotsOfAnUnlistedDeviceFromAPage() {
        defer { fixture.remove() }
        let plan = CustomPagePlanner.plan(
            local: CustomPageContent(), config: Self.config,
            remote: pages(placements: [Placed.placement("p1", asset: "a1", group: Self.iPad.placementGroup)])
        )

        #expect(plan.sets.map(\.deviceClass) == [Self.iPad])
        #expect(plan.sets.first?.action == .replace(removing: 1, adding: 0))
    }

    /// A page takes no watch screenshots, so a watch group is never its own.
    @Test func leavesADeviceClassThePageDoesNotTake() {
        defer { fixture.remove() }
        let plan = CustomPagePlanner.plan(
            local: CustomPageContent(), config: Self.config,
            remote: pages(placements: [Placed.placement("p1", asset: "a1", group: Self.watch.placementGroup)])
        )

        #expect(plan.sets.isEmpty)
    }
}
