import ASCKitAPI
import Foundation

/// What the last read of App Store Connect found in the custom product pages,
/// kept in `cache/`.
///
/// A caller with no network and no key reads this to know that a page exists,
/// whether it takes changes, and which keywords it can use. Never in the
/// repository, like the rest of the cache.
public struct CustomPageSnapshot: Codable, Sendable, Equatable {
    public struct Page: Codable, Sendable, Equatable {
        public let id: String
        public let name: String
        /// The folder under `custom-product-pages`.
        public let folder: String
        public let state: String?
        public let isEditable: Bool
        public let visible: Bool
        public let url: String?
        public let deepLink: String?
        /// The languages App Store Connect holds a page for.
        public let locales: [String]
    }

    public let readOn: Date
    public let pages: [Page]

    /// The keywords a page can use, by language.
    public let keywords: [String: [String]]

    public init(_ remote: RemoteCustomPages, readOn: Date = .now) {
        let names = CustomPageFolders.folderNames(for: remote)
        self.readOn = readOn
        keywords = remote.keywords
        pages = remote.pages.map { page in
            Page(
                id: page.id,
                name: page.name,
                folder: names[page.id] ?? page.name,
                state: page.version?.state?.rawValue,
                isEditable: page.isEditable,
                visible: page.visible,
                url: page.url,
                deepLink: page.version?.deepLink,
                locales: page.version?.localizations.map(\.locale).sorted() ?? []
            )
        }
    }

    public func page(folder: String) -> Page? {
        pages.first { $0.folder == folder }
    }
}

public enum CustomPageSnapshotStore {
    public static func url(in project: Project) -> URL {
        project.cacheURL.appending(path: "custom-product-pages.json")
    }

    /// Nil until something has read the pages.
    public static func load(in project: Project) -> CustomPageSnapshot? {
        guard let data = try? Data(contentsOf: url(in: project)) else { return nil }
        return try? ProjectJSON.decoder(datesAsISO8601: true).decode(CustomPageSnapshot.self, from: data)
    }

    public static func save(_ snapshot: CustomPageSnapshot, in project: Project) throws {
        let url = url(in: project)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try ProjectJSON.write(snapshot, to: url, datesAsISO8601: true)
    }
}
