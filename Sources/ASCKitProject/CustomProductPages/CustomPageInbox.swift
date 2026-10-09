import ASCKitAPI
import Foundation

/// Images waiting to go into a custom product page.
///
///     inbox/custom-product-pages/<page>/03-shopping-iPhone-6.9-en_US.png
///
/// The folder says which page. The file name says the language and the device
/// class, in the same format as every other waiting image. Folders deeper than
/// the page say nothing extra.
///
/// The folder names are the ones `CustomPageFolders` makes.
public enum CustomPageInbox {
    public static func url(in project: Project) -> URL {
        Inbox.url(in: project).appending(path: CustomPageFolders.folderName)
    }

    /// What one waiting image would do.
    public struct Arrival: Sendable, Hashable, Identifiable {
        public let file: ScreenshotFile
        public let slot: CustomPageSlot
        public let deviceClass: DeviceClass
        public let imageName: String
        public var id: URL { file.url }
    }

    public struct Refusal: Sendable, Hashable, Identifiable {
        public let file: ScreenshotFile
        public let reason: String
        public var id: URL { file.url }
    }

    public struct Plan: Sendable, Hashable {
        public var arrivals: [Arrival] = []
        public var refusals: [Refusal] = []

        public var isEmpty: Bool { arrivals.isEmpty && refusals.isEmpty }

        /// The arrivals that go into one slot.
        public struct Group: Sendable {
            public let slot: CustomPageSlot
            public let deviceClass: DeviceClass
            public var arrivals: [Arrival]
        }

        /// The arrivals gathered by slot, in the order they arrived. One slot
        /// is written at a time, because the limit of ten is counted per slot.
        public var groups: [Group] {
            var groups: [Group] = []
            for arrival in arrivals {
                if let index = groups.firstIndex(where: { $0.slot == arrival.slot }) {
                    groups[index].arrivals.append(arrival)
                } else {
                    groups.append(Group(slot: arrival.slot, deviceClass: arrival.deviceClass, arrivals: [arrival]))
                }
            }
            return groups
        }
    }

    /// The images waiting under the folder, in name order.
    public static func waiting(in project: Project) -> [ScreenshotFile] {
        let entries = FileManager.default.enumerator(
            at: url(in: project),
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        )?.compactMap { $0 as? URL } ?? []

        return entries
            .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false }
            .sortedNaturally(by: \.path)
            .map(ImageInspector.inspect)
            .filter { $0.pixelWidth != nil }
    }

    /// Reads the folder and works out where each image goes, with the pages
    /// the last read of App Store Connect found.
    ///
    /// Only a page that takes changes takes images. ASCKit never makes a page,
    /// so an image in a folder that names none is refused with the names that
    /// do exist.
    ///
    /// With no snapshot, a page folder already on disk takes images, the way a
    /// treatment folder does. The read only makes folders for pages that take
    /// changes.
    public static func plan(in project: Project, snapshot: CustomPageSnapshot?) -> Plan {
        let editable = if let snapshot {
            Set(snapshot.pages.filter(\.isEditable).map(\.folder))
        } else {
            Set(DirectoryListing.directories(in: project.customPagesURL).map(\.lastPathComponent))
        }
        return plan(
            waiting(in: project), root: url(in: project), editable: editable, config: project.config,
            refData: RefDataCache.load(in: project)
        )
    }

    static func plan(
        _ files: [ScreenshotFile],
        root: URL,
        editable: Set<String>,
        config: ProjectConfig,
        refData: AssetLibraryRefData? = nil
    ) -> Plan {
        var plan = Plan()
        let rootParts = root.standardizedFileURL.pathComponents

        for file in files {
            let parts = Array(file.url.standardizedFileURL.pathComponents.dropFirst(rootParts.count))
            // The page folder, and the file itself.
            guard parts.count >= 2 else {
                plan.refusals.append(Refusal(file: file, reason: String(
                    localized: """
                    \(file.fileName) is not in a page folder. Put it in \
                    \(CustomPageFolders.folderName)/<page>/.
                    """, bundle: .module
                )))
                continue
            }
            let page = parts[0]

            guard editable.contains(page) else {
                let names = editable.sorted().joined(separator: ", ")
                plan.refusals.append(Refusal(file: file, reason: String(
                    localized: """
                    \(page) is not a custom product page that takes changes. \
                    Read App Store Connect to make the folders. Known: \(names).
                    """, bundle: .module
                )))
                continue
            }

            switch ScreenshotNaming.read(file.fileName, config: config) {
            case let .success(named):
                if let reason = ContentWriter.reasonToRefuse(file, for: named.deviceClass, refData: refData) {
                    plan.refusals.append(Refusal(file: file, reason: reason))
                } else {
                    plan.arrivals.append(Arrival(
                        file: file,
                        slot: CustomPageSlot(page: page, locale: named.locale, deviceClassID: named.deviceClass.id),
                        deviceClass: named.deviceClass,
                        imageName: named.imageName
                    ))
                }
            case let .failure(refusal):
                plan.refusals.append(Refusal(file: file, reason: refusal.description))
            }
        }
        return plan
    }

    /// What filing did.
    public struct Outcome: Sendable {
        public var filed: Int
        public var slots: [CustomPageSlot]

        /// Where replaced files went, so a caller can point at them.
        public var trashed: [URL]
    }

    /// Puts each accepted image in its page's folder and moves the inbox copy
    /// to the Trash. The inbox copy may be the only copy of that artwork.
    @discardableResult
    public static func file(
        _ plan: Plan,
        replacingExisting: Bool = false,
        in project: Project
    ) throws -> Outcome {
        var outcome = Outcome(filed: 0, slots: [], trashed: [])

        for group in plan.groups {
            let written = try ContentWriter.addCustomPageScreenshots(
                from: group.arrivals.map(\.file.url),
                slot: group.slot,
                deviceClass: group.deviceClass,
                replacingExisting: replacingExisting,
                in: project
            )
            outcome.trashed += written.trashed

            for arrival in group.arrivals {
                var landed: NSURL?
                try FileManager.default.trashItem(at: arrival.file.url, resultingItemURL: &landed)
                if let landed = landed as URL? { outcome.trashed.append(landed) }
            }
            outcome.filed += group.arrivals.count
            outcome.slots.append(group.slot)
        }
        return outcome
    }
}

// MARK: - Writing the text

public extension ContentWriter {
    /// Writes the words of one language of a page. A field that is nil is
    /// left out of the file, and so left alone on App Store Connect.
    static func writeCustomPageText(_ text: CustomPageText, page: String, in project: Project) throws {
        try CustomPageFolders.write(text, to: project.customPageTextURL(page: page, locale: text.locale))
    }

    static func writeCustomPageSettings(_ settings: CustomPageSettings, page: String, in project: Project) throws {
        try CustomPageFolders.write(settings, to: project.customPageSettingsURL(page: page))
    }
}
