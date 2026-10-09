import ASCKitAPI
import Foundation

public extension PushSession {
    /// The custom product pages on App Store Connect, what is on disk for
    /// them, and what a push would change.
    struct CustomPageReading: Sendable {
        public let remote: RemoteCustomPages
        public let content: CustomPageContent
        public let plan: CustomPagePlan

        /// The empty folders this read made, one for each language of each
        /// page that takes changes, so images can be dropped straight in.
        public let madeFolders: [URL]

        /// The text files this read wrote, for languages that had none.
        public let seededFiles: [URL]

        /// The app's library and the record of it.
        public var library: LibraryState
    }

    /// Reads the pages and makes their folders and text files.
    ///
    /// Writes nothing to App Store Connect. On disk it makes only empty
    /// folders and text files that are not there yet, and only when
    /// `makeFolders` is true.
    func readCustomPages(makeFolders: Bool = true) async throws -> CustomPageReading {
        let remote = try await client.customPages(bundleID: project.config.bundleID)
        guard let library = try await readLibrary(appID: remote.appID, listing: nil) else {
            throw LibraryReadError.noLibrary
        }
        let made = makeFolders ? try CustomPageFolders.scaffold(remote, in: project) : []
        let seeded = makeFolders ? try CustomPageFolders.seed(remote, in: project) : []

        // A cache, so a failure here must not stop the read.
        try? CustomPageSnapshotStore.save(CustomPageSnapshot(remote), in: project)
        let content = CustomPageContentStore.load(in: project)
        return CustomPageReading(
            remote: remote,
            content: content,
            plan: CustomPagePlanner.plan(
                local: content, config: project.config, remote: remote, record: library.record
            ),
            madeFolders: made,
            seededFiles: seeded,
            library: library
        )
    }

    /// Writes the deep links, the promotional text and the keywords, then
    /// files the record of it.
    @discardableResult
    func pushCustomPageText(
        _ reading: CustomPageReading,
        at date: Date = .now,
        progress: (@Sendable (String) -> Void)? = nil
    ) async -> Outcome<CustomPageTextPusher.Result> {
        let result = await CustomPageTextPusher(client: client).push(reading.plan, progress: progress)
        return file(PushReceipt.forCustomPageText(result, at: date), for: result)
    }

    /// Uploads the images of the pages, then files the record of it.
    @discardableResult
    func pushCustomPageImages(
        _ reading: CustomPageReading,
        at date: Date = .now,
        progress: (@Sendable (ScreenshotPusher.Step) -> Void)? = nil
    ) async -> Outcome<ScreenshotPusher.Result> {
        let result = await pushToLibrary(
            Self.targets(in: reading.plan), library: reading.library, at: date, progress: progress
        )
        return file(PushReceipt.forExperimentImages(result, kind: .customPageImages, at: date), for: result)
    }
}

extension PushSession {
    static func targets(in plan: CustomPagePlan) -> [LibraryPusher.Target] {
        let screenshots = plan.changingSets.map { item in
            LibraryPusher.Target(
                id: item.id,
                label: item.label,
                deviceClassID: item.deviceClass.id,
                parent: .customProductPageLocalization(id: item.localizationID),
                files: item.localFiles.map(\.libraryFile),
                slot: item.library
            )
        }
        let previews = plan.changingPreviewSets.map { item in
            LibraryPusher.Target(
                id: item.id,
                label: item.label,
                deviceClassID: item.deviceClass.id,
                parent: .customProductPageLocalization(id: item.localizationID),
                files: item.localFiles.map(\.libraryFile),
                slot: item.library
            )
        }
        let creative = plan.changingCreativeSets.map { item in
            LibraryPusher.Target(
                id: item.id,
                label: item.label,
                deviceClassID: item.plan.role.rawValue,
                parent: .customProductPageLocalization(id: item.localizationID),
                files: item.plan.file.map { [$0.libraryFile] } ?? [],
                slot: item.plan.library
            )
        }
        return screenshots + previews + creative
    }
}
