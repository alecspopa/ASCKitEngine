import ASCKitAPI
import Foundation

public extension Inbox {
    /// What filing did.
    struct Outcome: Sendable {
        /// How many images went into a set.
        public var filed: Int

        /// The languages of the version they went into, in the order they
        /// arrived.
        public var locales: [String]

        /// The treatments and custom product pages they went into.
        public var places: [LibraryContentPlace] = []

        /// Where inbox copies and replaced files went, so a caller can point
        /// at them rather than claiming they are gone.
        public var trashed: [URL]

        /// Languages that took the new pictures of the language beside them,
        /// because `copiesScreenshotsFrom` says they do.
        public var copied: [SiblingScreenshots.Remembered] = []

        /// The header and search results images that went in.
        public var creative: [CreativeArrival] = []
    }

    /// Puts every image the plan accepts into the set its folder and its name
    /// name, and takes the inbox copy away.
    ///
    /// The inbox copy goes to the Trash rather than being deleted. The file
    /// somebody dropped there may be the only copy of that artwork anybody has.
    ///
    /// A place App Store Connect takes no change for is refused with a lock
    /// before anything moves: a `ScreenshotLock` for the version, and a
    /// `ScreenshotPlaceLock` for a treatment or a page that locked since the
    /// plan was read. With no listing and no read, filing goes ahead, and the
    /// push refuses later.
    ///
    /// With `replacingExisting`, an image that shows the same thing as one in
    /// the set takes its place. Without it, it is added as another file.
    ///
    /// One set at a time. A set that would pass the limit of ten stops there,
    /// and the images already filed stay filed.
    ///
    /// A language of the version that copies one of these sets takes the new
    /// pictures too, so an export that lands in `es-MX` is in `es-ES` when this
    /// returns.
    @discardableResult
    static func file(
        _ plan: Plan,
        places: Places,
        in project: Project,
        replacingExisting: Bool = false
    ) throws -> Outcome {
        var version: String?
        if plan.hasVersionArrivals {
            guard let named = places.version else { throw InboxError.noVersionFolder }
            try ScreenshotLock.refuse(version: named, listing: places.listing)
            version = named
        }
        for place in Set(plan.groups.compactMap(\.place) + plan.creative.compactMap(\.place)) {
            try ScreenshotPlaceLock.refuse(place, listing: nil, experiments: places.experiments, pages: places.pages)
        }

        var outcome = Outcome(filed: 0, locales: [], trashed: [])
        for group in plan.groups {
            let place = group.place ?? .version(version ?? "")
            let write = try ContentWriter.addScreenshots(
                from: group.arrivals.map(\.file.url),
                locale: group.locale,
                deviceClass: group.deviceClass,
                at: place,
                replacingExisting: replacingExisting,
                in: project
            )
            outcome.trashed.append(contentsOf: write.trashed)

            // Only once the copy is in the set. An image trashed with nothing
            // to show for it is the one outcome worth taking care over.
            for arrival in group.arrivals {
                var landed: NSURL?
                try FileManager.default.trashItem(at: arrival.file.url, resultingItemURL: &landed)
                if let landed = landed as URL? { outcome.trashed.append(landed) }
            }
            outcome.filed += group.arrivals.count
            if let place = group.place {
                if outcome.places.contains(place) == false { outcome.places.append(place) }
            } else if outcome.locales.contains(group.locale) == false {
                outcome.locales.append(group.locale)
            }
        }

        try fileCreative(plan.creative, version: version, in: project, into: &outcome)

        removeEmptiedFolders(plan.arrivals.map(\.file.url) + plan.creative.map(\.file.url), in: project)

        if let version {
            let changed = Set(plan.groups.filter { $0.place == nil }.map {
                ScreenshotSlot(locale: $0.locale, deviceClassID: $0.deviceClass.id)
            })
            outcome.copied = try SiblingScreenshots.copyRemembered(version: version, in: project, after: changed)
        }
        return outcome
    }

    /// The same, with the tests and pages the last read left in the cache.
    @discardableResult
    static func file(
        _ plan: Plan,
        version: String?,
        listing: RemoteListing?,
        in project: Project,
        replacingExisting: Bool = false
    ) throws -> Outcome {
        try file(
            plan,
            places: .cached(version: version, listing: listing, in: project),
            in: project,
            replacingExisting: replacingExisting
        )
    }

    /// Removes the subfolders that filing these files left empty, up to the
    /// inbox itself.
    ///
    /// Only the folders these files were in. An empty folder a person made
    /// for the next export stays. A folder that holds only hidden files, such
    /// as the `.DS_Store` the Finder writes, counts as empty.
    private static func removeEmptiedFolders(_ filed: [URL], in project: Project) {
        let inbox = url(in: project).standardizedFileURL.path
        var folders = Set(filed.map { $0.deletingLastPathComponent().standardizedFileURL })

        while let folder = folders.popFirst() {
            guard folder.path.hasPrefix(inbox + "/") else { continue }
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path),
                  names.allSatisfy({ $0.hasPrefix(".") })
            else { continue }

            // Nothing a person can see is lost, so this removes rather than
            // trashes, and a failure leaves only an empty folder behind.
            guard (try? FileManager.default.removeItem(at: folder)) != nil else { continue }
            folders.insert(folder.deletingLastPathComponent().standardizedFileURL)
        }
    }
}

/// Why the inbox filed nothing.
public enum InboxError: Error, Equatable, CustomLocalizedStringResourceConvertible {
    case noVersionFolder

    public var localizedStringResource: LocalizedStringResource {
        switch self {
        case .noVersionFolder:
            LocalizedStringResource(
                "This project has no version folder yet, so there is nowhere to file these.", bundle: .here
            )
        }
    }
}
