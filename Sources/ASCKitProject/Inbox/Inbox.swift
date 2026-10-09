import ASCKitAPI
import Foundation

/// The folder a screenshot waits in before it goes into a set.
///
/// Reads the folder and works out where each image belongs. The name of a
/// waiting file says which language and which device class it is for, so
/// nothing is left to ask a person. `ScreenshotNaming` is what reads it.
public enum Inbox {
    /// Where images wait, for one project.
    public static func url(in project: Project) -> URL {
        project.rootURL.appending(path: ProjectScaffold.inboxName)
    }

    // MARK: - What is waiting

    /// The images in the inbox now, in its subfolders too, in name order.
    ///
    /// Images only. The folder holds its own `.gitignore`, and a person can put
    /// anything else in a folder they can see. A file that does not read as an
    /// image is left where it is and nothing is said about it.
    ///
    /// A design tool exports one folder per language, and the file name says
    /// where each image goes, so the folders it sits in say nothing extra.
    public static func waiting(in project: Project) -> [ScreenshotFile] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        let entries = FileManager.default.enumerator(
            at: url(in: project),
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        )?.compactMap { $0 as? URL } ?? []

        // What waits in the Product Page Optimization folder goes to a
        // treatment, and `ExperimentInbox` files it.
        let experiments = ExperimentInbox.url(in: project).standardizedFileURL.path + "/"

        return entries
            .filter { $0.standardizedFileURL.path.hasPrefix(experiments) == false }
            .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) ?? false }
            .sorted {
                let (lhs, rhs) = ($0.lastPathComponent, $1.lastPathComponent)
                if lhs.isNaturallyBefore(rhs) { return true }
                if rhs.isNaturallyBefore(lhs) { return false }
                return $0.path < $1.path
            }
            .map(ImageInspector.inspect)
            .filter { $0.pixelWidth != nil }
    }

    // MARK: - Where it would go

    /// One waiting image, and the slot its name sends it to.
    public struct Arrival: Sendable, Hashable, Identifiable {
        public let file: ScreenshotFile
        public let locale: String
        public let deviceClass: DeviceClass

        /// What the screenshot shows, which is its name without the number,
        /// the device class and the language.
        public let imageName: String

        public var id: URL { file.url }

        public init(
            file: ScreenshotFile,
            locale: String,
            deviceClass: DeviceClass,
            imageName: String
        ) {
            self.file = file
            self.locale = locale
            self.deviceClass = deviceClass
            self.imageName = imageName
        }
    }

    /// One waiting image this project has nowhere to put, and why.
    public struct Refusal: Sendable, Hashable, Identifiable {
        public let file: ScreenshotFile
        public let reason: String

        /// Whether the file name cannot say where its image goes.
        public let hasInvalidName: Bool

        /// The device class the name asks for, when the project not listing it
        /// is the whole reason. `DeviceClassAdoption` is what acts on this: the
        /// image can be filed as it is once the project lists that device
        /// class, so nothing has to be renamed.
        public let unlistedDeviceClass: DeviceClass?

        /// Whether an alpha channel is the whole reason. `AlphaRemoval` is what
        /// acts on this: the image can be written again without the channel and
        /// filed as it is, so nothing has to be exported a second time.
        public let hasClearableAlpha: Bool

        public var id: URL { file.url }

        public init(
            file: ScreenshotFile,
            reason: String,
            hasInvalidName: Bool = false,
            unlistedDeviceClass: DeviceClass? = nil,
            hasClearableAlpha: Bool = false
        ) {
            self.file = file
            self.reason = reason
            self.hasInvalidName = hasInvalidName
            self.unlistedDeviceClass = unlistedDeviceClass
            self.hasClearableAlpha = hasClearableAlpha
        }
    }

    /// The arrivals that go into one slot, which is one language and one device
    /// class.
    public struct Group: Sendable, Hashable {
        public let locale: String
        public let deviceClass: DeviceClass
        public var arrivals: [Arrival]
    }

    /// What is waiting, split into what can be filed and what cannot.
    public struct Plan: Sendable, Hashable {
        public var arrivals: [Arrival]
        public var refusals: [Refusal]

        public init(arrivals: [Arrival] = [], refusals: [Refusal] = []) {
            self.arrivals = arrivals
            self.refusals = refusals
        }

        public var isEmpty: Bool { arrivals.isEmpty && refusals.isEmpty }
        public var count: Int { arrivals.count + refusals.count }

        /// Every waiting image, whatever is going to happen to it.
        public var files: [ScreenshotFile] { arrivals.map(\.file) + refusals.map(\.file) }

        /// Whether a waiting file must be renamed before it can be filed.
        public var hasInvalidNames: Bool {
            refusals.contains { $0.hasInvalidName }
        }

        /// The languages the arrivals go to, in the order they arrived.
        public var locales: [String] {
            var seen: [String] = []
            for arrival in arrivals where seen.contains(arrival.locale) == false {
                seen.append(arrival.locale)
            }
            return seen
        }

        /// The arrivals gathered by slot, in the order they arrived.
        ///
        /// One slot is written at a time, because the limit of ten screenshots
        /// is counted per slot.
        public var groups: [Group] {
            var groups: [Group] = []
            for arrival in arrivals {
                let index = groups.firstIndex {
                    $0.locale == arrival.locale && $0.deviceClass == arrival.deviceClass
                }
                if let index {
                    groups[index].arrivals.append(arrival)
                } else {
                    groups.append(Group(
                        locale: arrival.locale,
                        deviceClass: arrival.deviceClass,
                        arrivals: [arrival]
                    ))
                }
            }
            return groups
        }
    }

    /// Reads the inbox and works out where each image would go.
    public static func plan(in project: Project) -> Plan {
        plan(waiting(in: project), config: project.config, refData: RefDataCache.load(in: project))
    }

    /// Where each of these images goes, read off its name.
    ///
    /// The name says the language and the device class. The image itself has
    /// to agree: a file the named device class would refuse is refused here,
    /// with the pixel sizes that device class does take.
    public static func plan(
        _ files: [ScreenshotFile], config: ProjectConfig, refData: AssetLibraryRefData? = nil
    ) -> Plan {
        var plan = Plan()
        for file in files {
            switch ScreenshotNaming.read(file.fileName, config: config) {
            case let .success(parts):
                let clearable = ContentWriter.onlyTheAlphaChannelRefuses(
                    file, for: parts.deviceClass, refData: refData
                )
                if let reason = ContentWriter.reasonToRefuse(file, for: parts.deviceClass, refData: refData) {
                    plan.refusals.append(Refusal(
                        file: file,
                        // A channel that can be cleared is said in one line.
                        // What to do about it is offered beside this, in the
                        // sheet and in the terminal both, so a refusal that
                        // said it as well would say it twice.
                        reason: clearable ? "\(file.fileName) has an alpha channel." : reason,
                        hasClearableAlpha: clearable
                    ))
                } else {
                    plan.arrivals.append(Arrival(
                        file: file,
                        locale: parts.locale,
                        deviceClass: parts.deviceClass,
                        imageName: parts.imageName
                    ))
                }

            case let .failure(refusal):
                plan.refusals.append(Refusal(
                    file: file,
                    reason: refusal.description,
                    hasInvalidName: refusal.hasInvalidName,
                    unlistedDeviceClass: refusal.unlistedDeviceClass
                ))
            }
        }
        return plan
    }

    // MARK: - Filing it

    /// What filing did.
    public struct Outcome: Sendable {
        /// How many images went into a set.
        public var filed: Int

        /// The languages they went into, in the order they arrived.
        public var locales: [String]

        /// Where inbox copies and replaced files went, so a caller can point
        /// at them rather than claiming they are gone.
        public var trashed: [URL]

        /// Languages that took the new pictures of the language beside them,
        /// because `copiesScreenshotsFrom` says they do.
        public var copied: [SiblingScreenshots.Remembered] = []
    }

    /// Puts every image the plan accepts into the language its name names, and
    /// takes the inbox copy away.
    ///
    /// The inbox copy goes to the Trash rather than being deleted. The file
    /// somebody dropped there may be the only copy of that artwork anybody has.
    ///
    /// A caller can allow matching screenshots to replace local files. This is
    /// for the App Store Connect version that still accepts screenshot changes.
    /// Without that permission, a matching screenshot is added as another file.
    ///
    /// One slot at a time. A set that would pass the limit of ten stops there,
    /// and the images already filed stay filed.
    ///
    /// A language that copies one of these sets takes the new pictures too, so
    /// an export that lands in `es-MX` is in `es-ES` when this returns.
    @discardableResult
    public static func file(
        _ plan: Plan,
        version: String,
        in project: Project,
        replacingExisting: Bool = false
    ) throws -> Outcome {
        var outcome = Outcome(filed: 0, locales: [], trashed: [])

        for group in plan.groups {
            if replacingExisting {
                let write = try ContentWriter.replaceScreenshots(
                    from: group.arrivals.map(\.file.url),
                    locale: group.locale,
                    deviceClass: group.deviceClass,
                    version: version,
                    in: project
                )
                outcome.trashed.append(contentsOf: write.trashed)
            } else {
                try ContentWriter.addScreenshots(
                    from: group.arrivals.map(\.file.url),
                    locale: group.locale,
                    deviceClass: group.deviceClass,
                    version: version,
                    in: project
                )
            }

            // Only once the copy is in the set. An image trashed with nothing
            // to show for it is the one outcome worth taking care over.
            for arrival in group.arrivals {
                var landed: NSURL?
                try FileManager.default.trashItem(at: arrival.file.url, resultingItemURL: &landed)
                if let landed = landed as URL? { outcome.trashed.append(landed) }
            }
            outcome.filed += group.arrivals.count
            if outcome.locales.contains(group.locale) == false {
                outcome.locales.append(group.locale)
            }
        }

        removeEmptiedFolders(plan.arrivals.map(\.file.url), in: project)

        let changed = Set(plan.groups.map {
            ScreenshotSlot(locale: $0.locale, deviceClassID: $0.deviceClass.id)
        })
        outcome.copied = try SiblingScreenshots.copyRemembered(
            version: version, in: project, after: changed
        )
        return outcome
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
