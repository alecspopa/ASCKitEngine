import ASCKitAPI
import Foundation

public extension Inbox {
    /// What the project knows about the places a waiting image can go: the
    /// version open, what App Store Connect says about it, and the last read
    /// of the tests and the custom product pages.
    ///
    /// A snapshot that is nil leaves the folders on disk to say which
    /// treatments and pages exist, and checks no language or lock for them.
    struct Places: Sendable {
        public var version: String?
        public var listing: RemoteListing?
        public var experiments: ExperimentSnapshot?
        public var pages: CustomPageSnapshot?

        public init(
            version: String? = nil,
            listing: RemoteListing? = nil,
            experiments: ExperimentSnapshot? = nil,
            pages: CustomPageSnapshot? = nil
        ) {
            self.version = version
            self.listing = listing
            self.experiments = experiments
            self.pages = pages
        }

        /// The snapshots the last read left in the project's cache.
        public static func cached(version: String?, listing: RemoteListing?, in project: Project) -> Places {
            Places(
                version: version,
                listing: listing,
                experiments: ExperimentSnapshotStore.load(in: project),
                pages: CustomPageSnapshotStore.load(in: project)
            )
        }
    }

    /// Reads the inbox and works out where each image would go.
    static func plan(in project: Project, places: Places = Places()) -> Plan {
        plan(
            waiting(in: project),
            root: url(in: project),
            known: KnownPlaces(project: project, places: places),
            config: project.config,
            refData: RefDataCache.load(in: project)
        )
    }

    /// Where each of these images goes, for images that all wait for the
    /// version, read off the name alone.
    static func plan(
        _ files: [ScreenshotFile], config: ProjectConfig, refData: AssetLibraryRefData? = nil
    ) -> Plan {
        var plan = Plan()
        for file in files {
            plan.add(file, at: nil, config: config, refData: refData, known: nil)
        }
        return plan
    }

    /// The folder says the place and the name says the language and the
    /// device class. The image itself has to agree: a file the named device
    /// class would refuse is refused here, with the pixel sizes that device
    /// class does take.
    internal static func plan(
        _ files: [ScreenshotFile],
        root: URL,
        known: KnownPlaces,
        config: ProjectConfig,
        refData: AssetLibraryRefData?
    ) -> Plan {
        var plan = Plan()
        let rootParts = root.standardizedFileURL.pathComponents

        for file in files {
            let parts = Array(file.url.standardizedFileURL.pathComponents.dropFirst(rootParts.count))
            switch known.place(of: file, parts: parts) {
            case let .refused(reason, place):
                plan.refusals.append(Refusal(file: file, reason: reason, place: place))
            case let .found(place):
                plan.add(file, at: place, config: config, refData: refData, known: known)
            }
        }
        return plan
    }
}

extension Inbox.Plan {
    /// Adds one waiting file whose place is known, or the reason it is
    /// refused. Nil is the version.
    mutating func add(
        _ file: ScreenshotFile,
        at place: LibraryContentPlace?,
        config: ProjectConfig,
        refData: AssetLibraryRefData?,
        known: Inbox.KnownPlaces?
    ) {
        let folderLocale = ScreenshotNaming.folderLocale(of: file.url, config: config)
        if let creative = ScreenshotNaming.readCreative(file.fileName, config: config, folderLocale: folderLocale) {
            addCreative(file, named: creative, at: place, config: config, refData: refData)
            return
        }

        switch ScreenshotNaming.read(file.fileName, config: config, folderLocale: folderLocale) {
        case let .success(parts):
            if let place, let reason = known?.refusal(locale: parts.locale, deviceClass: parts.deviceClass, at: place) {
                refusals.append(Inbox.Refusal(file: file, reason: reason, place: place))
            } else if let refused = ContentWriter.inboxRefusal(file, for: parts.deviceClass, refData: refData) {
                refusals.append(Inbox.Refusal(
                    file: file, reason: refused.reason, place: place, hasClearableAlpha: refused.hasClearableAlpha
                ))
            } else {
                arrivals.append(Inbox.Arrival(
                    file: file, place: place, locale: parts.locale, deviceClass: parts.deviceClass,
                    imageName: parts.imageName
                ))
            }

        case let .failure(refusal):
            refusals.append(Inbox.Refusal(
                file: file,
                reason: refusal.description,
                place: place,
                hasInvalidName: refusal.hasInvalidName,
                unlistedDeviceClass: refusal.unlistedDeviceClass
            ))
        }
    }
}
