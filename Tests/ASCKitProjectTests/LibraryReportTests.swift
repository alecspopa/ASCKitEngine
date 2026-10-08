import ASCKitAPI
import Foundation
import Testing
@testable import ASCKitProject

struct LibraryReportTests {
    static func listing(
        sets: [RemoteScreenshotSet] = [],
        placements: [RemotePlacement] = []
    ) -> RemoteListing {
        RemoteListing(
            appID: "app1", appName: "Demo", bundleID: "com.example.Demo",
            appInfoID: nil, appInfoState: nil,
            versionID: "v1", versionString: "2.0", versionState: .prepareForSubmission,
            appInfoLocalizations: [:],
            versionLocalizations: [
                "en-US": RemoteLocalization(id: "l-en", locale: "en-US", values: [:]),
                "de-DE": RemoteLocalization(id: "l-de", locale: "de-DE", values: [:])
            ],
            screenshotSets: sets,
            placements: placements
        )
    }

    static func placement(_ id: String, locale: String = "en-US", type: PlacementType = .appScreenshot,
                          group: String = "IPHONE_DYNAMIC_ISLAND_LARGE_PROFILE", file: String) -> RemotePlacement {
        RemotePlacement(
            id: id, locale: locale, type: type, group: group, state: .parentPrepareForSubmission,
            asset: RemoteLibraryAsset(id: "a-\(id)", media: type == .appPreview ? .video : .image, fileName: file)
        )
    }

    @Test func saysWhenTheAppHasNoLibrary() {
        let lines = LibraryReport.lines(library: nil, listing: Self.listing())
        #expect(lines.first == "This app has no asset library on App Store Connect.")
    }

    @Test func countsTheImagesAndVideosAndTheirPlacements() {
        let library = RemoteAssetLibrary(
            id: "lib1",
            assets: [
                RemoteLibraryAsset(id: "a", media: .image, fileName: "01.png", referenceName: "Menu", state: .approved),
                RemoteLibraryAsset(id: "b", media: .video, fileName: "preview.mov", state: .uploadComplete)
            ],
            placementIDs: ["a": ["p1", "p2"]]
        )

        let lines = LibraryReport.libraryLines(library)

        #expect(lines == [
            "Asset library lib1. Images: 1. Videos: 1.",
            "  01.png \"Menu\": image, APPROVED. Placements: 2.",
            "  preview.mov: video, UPLOAD_COMPLETE. Placements: 0."
        ])
    }

    @Test func showsTheOldSetsNextToThePlacementsOfEachLanguage() {
        let set = RemoteScreenshotSet(
            id: "s1", locale: "en-US", displayType: .appIPhone67,
            screenshots: [
                RemoteScreenshot(id: "x", fileName: "01.png", fileSize: 1, sourceFileChecksum: "c"),
                RemoteScreenshot(id: "y", fileName: "02.png", fileSize: 1, sourceFileChecksum: "d")
            ]
        )
        let listing = Self.listing(sets: [set], placements: [
            Self.placement("p2", file: "02.png"),
            Self.placement("p1", file: "01.png"),
            Self.placement("p3", type: .appPreview, file: "preview.mov")
        ])

        let lines = LibraryReport.lines(library: nil, listing: listing)

        #expect(Array(lines.dropFirst(2)) == [
            "Version 2.0, PREPARE_FOR_SUBMISSION",
            "  de-DE",
            "    Old screenshot sets: 0. Images in them: 0.",
            "    Placements: none.",
            "  en-US",
            "    Old screenshot sets: 1. Images in them: 2.",
            "    APP_SCREENSHOT IPHONE_DYNAMIC_ISLAND_LARGE_PROFILE: 02.png, 01.png",
            "    APP_PREVIEW IPHONE_DYNAMIC_ISLAND_LARGE_PROFILE: preview.mov"
        ])
    }

    @Test func keepsTheStoresOrderWithinEachGroup() {
        let slots = LibraryReport.slots(of: [
            Self.placement("1", group: "B", file: "b1"),
            Self.placement("2", group: "A", file: "a1"),
            Self.placement("3", group: "B", file: "b2")
        ])
        #expect(slots.map(\.group) == ["B", "A"])
        #expect(slots[0].placements.map(\.id) == ["1", "3"])
    }

    @Test func namesAPlacementWithNoTypeOrGroupOrAsset() {
        let odd = RemotePlacement(id: "p", locale: "en-US", type: nil, group: nil, state: nil, asset: nil)
        let lines = LibraryReport.localeLines(locales: ["en-US"], sets: [], placements: [odd], indent: "")
        #expect(lines.last == "  unknown type unknown group: ?")
    }

    @Test func showsEachGroupWithItsTypesAndLimits() {
        let data = AssetLibraryRefData(
            features: [.init(featureId: "APP_STORE_VERSIONS", placementPolicies: [
                .init(placementType: .appScreenshot, groupLimits: [.init(groupIds: ["IPHONE_DUO_PROFILE"], maxCount: 10)])
            ])],
            placementProfileGroups: [
                .init(placementProfileGroupId: "MAC_PROFILE", platform: nil, displayClassId: "DEFAULT"),
                .init(placementProfileGroupId: "IPHONE_DUO_PROFILE", platform: "IPHONE_APP_STORE", displayClassId: "IPHONE_DUO")
            ],
            placementTypes: [
                .init(placementTypeId: .appScreenshot, acceptsAssetCategories: nil, specMappings: [
                    .init(placementGroupId: "IPHONE_DUO_PROFILE", specs: ["s"])
                ]),
                .init(placementTypeId: .appPreview, acceptsAssetCategories: nil, specMappings: [
                    .init(placementGroupId: "IPHONE_DUO_PROFILE", specs: ["v"])
                ])
            ]
        )

        #expect(LibraryReport.referenceLines(data) == [
            "Placement groups",
            "  IPHONE_DUO_PROFILE: IPHONE_APP_STORE, IPHONE_DUO",
            "    APP_SCREENSHOT (at most 10), APP_PREVIEW",
            "  MAC_PROFILE: no platform, DEFAULT",
            "    no placement types"
        ])
    }

    @Test func showsEachLanguageOfEachDraftTest() {
        let experiments = RemoteExperiments(appID: "app1", experiments: [
            RemoteExperiment(id: "e1", name: "Fall", state: .prepareForSubmission, platform: .ios, treatments: [
                RemoteTreatment(id: "t1", name: "Treatment A", localizations: [
                    RemoteTreatmentLocalization(id: "tl1", locale: "en-US", placements: [Self.placement("p", file: "a.png")])
                ])
            ])
        ])

        let lines = LibraryReport.lines(library: nil, listing: Self.listing(), experiments: experiments)

        #expect(Array(lines.suffix(4)) == [
            "",
            "Test Fall, Treatment A",
            "  en-US",
            "    APP_SCREENSHOT IPHONE_DYNAMIC_ISLAND_LARGE_PROFILE: a.png"
        ])
    }
}
