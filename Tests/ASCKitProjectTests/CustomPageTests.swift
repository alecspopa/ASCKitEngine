import ASCKitAPI
import ASCKitTestSupport
import Foundation
import Testing
@testable import ASCKitProject

final class CustomPageTests {
    let fixture: FixtureProject
    let project: Project
    let deviceClass = DeviceClass.iPhone69

    init() throws {
        fixture = try FixtureProject()
        let config = ProjectConfig(
            bundleID: "com.example.Demo",
            keyID: "ABC123",
            issuerID: "issuer",
            sourceLocale: "en-US",
            locales: ["en-US", "de-DE"],
            deviceClasses: [DeviceClass.iPhone69.id]
        )
        let url = try fixture.writeConfig(config)
        project = Project(configURL: url, config: config)
    }

    deinit {
        fixture.remove()
    }

    func remote(
        state: CustomPageVersionState = .prepareForSubmission,
        deepLink: String? = "moondane://sky",
        english: RemoteCustomPageLocalization = RemoteCustomPageLocalization(
            id: "cloc-en", locale: "en-US", promotionalText: "See the moon.", keywordIDs: ["moon"]
        )
    ) -> RemoteCustomPages {
        RemoteCustomPages(
            appID: "app1",
            pages: [RemoteCustomPage(
                id: "page1", name: "Night sky", url: nil, visible: true,
                version: RemoteCustomPageVersion(
                    id: "v2", version: "2", state: state, deepLink: deepLink,
                    localizations: [
                        english,
                        RemoteCustomPageLocalization(id: "cloc-de", locale: "de-DE", promotionalText: nil)
                    ]
                )
            )],
            keywords: ["en-US": ["moon", "stars"], "de-DE": ["mond"]]
        )
    }

    func slot(_ locale: String = "en-US") -> CustomPageSlot {
        CustomPageSlot(page: "Night sky", locale: locale, deviceClassID: deviceClass.id)
    }

    func writeImage(_ name: String, in slot: CustomPageSlot) throws {
        let directory = project.customPageURL(page: slot.page, locale: slot.locale, deviceClassID: slot.deviceClassID)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try PNGWriter.write(to: directory.appending(path: name), width: 1320, height: 2868, hasAlpha: false, seed: name)
    }

    func plan(_ remote: RemoteCustomPages) -> CustomPagePlan {
        CustomPagePlanner.plan(local: CustomPageContentStore.load(in: project), config: project.config, remote: remote)
    }

    // MARK: - Reading

    @Test func makesFoldersAndTextFilesForADraftPage() throws {
        let made = try CustomPageFolders.scaffold(remote(), in: project)
        let seeded = try CustomPageFolders.seed(remote(), in: project)

        #expect(made.count == 2)
        #expect(seeded.count == 3)

        let content = CustomPageContentStore.load(in: project)
        #expect(content.text(page: "Night sky", locale: "en-US")?.promotionalText == "See the moon.")
        #expect(content.text(page: "Night sky", locale: "en-US")?.keywords == ["moon"])
        #expect(content.settings["Night sky"]?.deepLink == "moondane://sky")
        #expect(try CustomPageFolders.scaffold(remote(), in: project).isEmpty)
    }

    /// A text file is what a person wants. A second read must not put back
    /// what App Store Connect holds.
    @Test func neverWritesOverATextFile() throws {
        try CustomPageFolders.seed(remote(), in: project)
        try ContentWriter.writeCustomPageText(
            CustomPageText(locale: "en-US", promotionalText: "Mine."), page: "Night sky", in: project
        )

        #expect(try CustomPageFolders.seed(remote(), in: project).isEmpty)
        #expect(CustomPageContentStore.load(in: project).text(page: "Night sky", locale: "en-US")?.promotionalText
            == "Mine.")
    }

    /// A language with no keywords at the first read leaves the links alone,
    /// so a keyword linked later in App Store Connect stays linked.
    @Test func leavesKeywordsAloneForALanguageThatHadNone() throws {
        try CustomPageFolders.seed(remote(), in: project)

        let later = RemoteCustomPages(
            appID: "app1",
            pages: [RemoteCustomPage(
                id: "page1", name: "Night sky", url: nil, visible: true,
                version: RemoteCustomPageVersion(
                    id: "v2", version: "2", state: .prepareForSubmission, deepLink: "moondane://sky",
                    localizations: [
                        RemoteCustomPageLocalization(
                            id: "cloc-en", locale: "en-US", promotionalText: "See the moon.", keywordIDs: ["moon"]
                        ),
                        RemoteCustomPageLocalization(
                            id: "cloc-de", locale: "de-DE", promotionalText: nil, keywordIDs: ["mond"]
                        )
                    ]
                )
            )]
        )

        #expect(CustomPageContentStore.load(in: project).text(page: "Night sky", locale: "de-DE")?.keywords == nil)
        #expect(plan(later).hasChanges == false)
    }

    @Test func makesNothingForAnApprovedPage() throws {
        #expect(try CustomPageFolders.scaffold(remote(state: .approved), in: project).isEmpty)
        #expect(try CustomPageFolders.seed(remote(state: .approved), in: project).isEmpty)
    }

    // MARK: - Planning

    @Test func plansNothingRightAfterTheFirstRead() throws {
        try CustomPageFolders.scaffold(remote(), in: project)
        try CustomPageFolders.seed(remote(), in: project)

        #expect(plan(remote()).hasChanges == false)
    }

    @Test func plansTheTextAndTheKeywords() throws {
        try ContentWriter.writeCustomPageText(
            CustomPageText(locale: "en-US", promotionalText: "New words.", keywords: ["stars"]),
            page: "Night sky", in: project
        )

        let change = try #require(plan(remote()).changingTexts.first)
        #expect(change.localizationID == "cloc-en")
        #expect(change.promotionalText == "New words.")
        #expect(change.keywordsToLink == ["stars"])
        #expect(change.keywordsToUnlink == ["moon"])
    }

    /// An empty box would blank the field on the store, so it is left alone.
    @Test func leavesEmptyPromotionalTextAlone() throws {
        try ContentWriter.writeCustomPageText(
            CustomPageText(locale: "en-US", promotionalText: ""), page: "Night sky", in: project
        )
        #expect(plan(remote()).hasChanges == false)
    }

    @Test func plansTheDeepLink() throws {
        try ContentWriter.writeCustomPageSettings(
            CustomPageSettings(deepLink: "moondane://moon"), page: "Night sky", in: project
        )

        let change = try #require(plan(remote()).deepLinkChanges.first)
        #expect(change.versionID == "v2")
        #expect(change.deepLink == "moondane://moon")
    }

    @Test func plansAnUploadForANewImage() throws {
        try writeImage("01-a-iPhone-6.9-en_US.png", in: slot())

        let plan = plan(remote())
        let set = try #require(plan.sets.first)
        #expect(set.localizationID == "cloc-en")
        #expect(set.action == .replace(removing: 0, adding: 1))
        #expect(PushSession.targets(in: plan).map(\.parent) == [.customProductPageLocalization(id: "cloc-en")])
    }

    /// Images placed in App Store Connect have no file here. An empty folder
    /// must not take them off.
    @Test func leavesTheImagesOfAnEmptyFolderAlone() throws {
        let placement = RemotePlacement(
            id: "p1", locale: "en-US", type: .appScreenshot, group: deviceClass.placementGroup,
            state: .parentPrepareForSubmission,
            asset: RemoteLibraryAsset(id: "a1", media: .image, fileName: "01-a.png", state: .approved)
        )
        let english = RemoteCustomPageLocalization(
            id: "cloc-en", locale: "en-US", promotionalText: nil, placements: [placement]
        )
        try FileManager.default.createDirectory(
            at: project.customPageURL(page: "Night sky", locale: "en-US", deviceClassID: deviceClass.id),
            withIntermediateDirectories: true
        )

        #expect(plan(remote(english: english)).hasChanges == false)
    }

    @Test func plansNothingForAnApprovedPage() throws {
        try writeImage("01-a-iPhone-6.9-en_US.png", in: slot())
        try ContentWriter.writeCustomPageText(
            CustomPageText(locale: "en-US", promotionalText: "New words."), page: "Night sky", in: project
        )

        let plan = plan(remote(state: .approved))
        #expect(plan.hasChanges == false)
        #expect(plan.unplaced.map(\.reason) == [.locked])
    }

    // MARK: - Checking

    @Test func reportsTextOverTheLimitAndAKeywordThatIsNotKnown() throws {
        try ContentWriter.writeCustomPageText(
            CustomPageText(
                locale: "en-US", promotionalText: String(repeating: "a", count: 171), keywords: ["comet"]
            ),
            page: "Night sky", in: project
        )

        let problems = Validator(project: project)
            .validate(CustomPageContentStore.load(in: project), keywords: remote().keywords)
        #expect(problems.contains { $0.kind == .textOverLimit && $0.locale == "en-US" })
        #expect(problems.contains { $0.kind == .customPageKeywordNotKnown })
    }

    @Test func refusesADeepLinkWithNoScheme() throws {
        try ContentWriter.writeCustomPageSettings(
            CustomPageSettings(deepLink: "sky"), page: "Night sky", in: project
        )

        let problems = Validator(project: project).validate(CustomPageContentStore.load(in: project))
        #expect(problems.contains { $0.kind == .customPageDeepLinkNotValid })
    }

    // MARK: - The inbox and the cache

    @Test func filesAWaitingImageIntoItsPage() throws {
        let snapshot = CustomPageSnapshot(remote())
        let inbox = CustomPageInbox.url(in: project).appending(path: "Night sky")
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        try PNGWriter.write(
            to: inbox.appending(path: "01-a-iPhone-6.9-en_US.png"), width: 1320, height: 2868, hasAlpha: false,
            seed: "a"
        )

        let plan = CustomPageInbox.plan(in: project, snapshot: snapshot)
        #expect(plan.refusals.isEmpty)
        #expect(plan.arrivals.map(\.slot) == [slot()])
        #expect(Inbox.waiting(in: project).isEmpty)
    }

    @Test func refusesAWaitingImageForAnApprovedPage() throws {
        let snapshot = CustomPageSnapshot(remote(state: .approved))
        let inbox = CustomPageInbox.url(in: project).appending(path: "Night sky")
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        try PNGWriter.write(
            to: inbox.appending(path: "01-a-iPhone-6.9-en_US.png"), width: 1320, height: 2868, hasAlpha: false,
            seed: "a"
        )

        #expect(CustomPageInbox.plan(in: project, snapshot: snapshot).refusals.count == 1)
    }

    @Test func keepsWhatTheReadFoundInTheCache() throws {
        try CustomPageSnapshotStore.save(CustomPageSnapshot(remote()), in: project)

        let snapshot = try #require(CustomPageSnapshotStore.load(in: project))
        #expect(snapshot.page(folder: "Night sky")?.isEditable == true)
        #expect(snapshot.page(folder: "Night sky")?.locales == ["de-DE", "en-US"])
        #expect(snapshot.keywords["en-US"] == ["moon", "stars"])
    }

    // MARK: - Pushing

    /// The deep link first, then the words, then the keyword links. A
    /// keyword goes off before a new one goes on, so a full page has room.
    @Test func writesTheDeepLinkTheTextAndTheKeywordsInOrder() async throws {
        try ContentWriter.writeCustomPageSettings(
            CustomPageSettings(deepLink: "moondane://moon"), page: "Night sky", in: project
        )
        try ContentWriter.writeCustomPageText(
            CustomPageText(locale: "en-US", promotionalText: "New words.", keywords: ["stars"]),
            page: "Night sky", in: project
        )
        let content = CustomPageContentStore.load(in: project)
        let reading = PushSession.CustomPageReading(
            remote: remote(),
            content: content,
            plan: CustomPagePlanner.plan(local: content, config: project.config, remote: remote()),
            madeFolders: [],
            seededFiles: [],
            library: LibraryState(libraryID: "lib0", record: AssetRecord())
        )
        let transport = StubTransport(routes: [
            ("/relationships/searchKeywords", .ok("")),
            ("/appCustomProductPageLocalizations/cloc-en", .ok("""
            {"data":{"type":"appCustomProductPageLocalizations","id":"cloc-en"}}
            """)),
            ("/appCustomProductPageVersions/v2", .ok("""
            {"data":{"type":"appCustomProductPageVersions","id":"v2"}}
            """))
        ])
        let session = try PushSession(project: project, client: ASCClient.stubbed(transport: transport))

        let outcome = await session.pushCustomPageText(reading)

        #expect(outcome.result.isCompleteSuccess)
        #expect(outcome.result.written == ["Night sky", "Night sky / en-US"])
        let requests = await transport.requests
        #expect(requests.map(\.httpMethod) == ["PATCH", "PATCH", "DELETE", "POST"])
        let deepLink = try #require(await transport.bodyText(at: 0))
        let unlinked = try #require(await transport.bodyText(at: 2))
        let linked = try #require(await transport.bodyText(at: 3))
        #expect(deepLink.contains("deepLink") && deepLink.contains("moon"))
        #expect(unlinked.contains(#""id":"moon""#))
        #expect(linked.contains(#""id":"stars""#))
    }

    @Test func countsTheChangesForThePublishSheet() throws {
        try ContentWriter.writeCustomPageText(
            CustomPageText(locale: "en-US", promotionalText: "New words."), page: "Night sky", in: project
        )

        let plan = plan(remote())
        #expect(PublishReadiness.availability(
            of: .customProductPages, given: .init(plan: nil, customPagePlan: plan)
        ) != .nothingToDo)
        #expect(PushProgress.steps(in: plan) == 1)
    }
}
