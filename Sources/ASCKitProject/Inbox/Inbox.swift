import ASCKitAPI
import Foundation

/// The folder a screenshot waits in before it goes into a set, for every
/// place: the version, a treatment of a test, and a custom product page.
///
///     inbox/03-shopping-iPhone-6.9-en_US.png                       the version
///     inbox/product-page-optimization/<test>/<treatment>/…png      a treatment
///     inbox/custom-product-pages/<page>/…png                       a custom product page
///
/// The folder says the place. The name of a waiting file says which language
/// and which device class it is for, so nothing is left to ask a person.
/// `ScreenshotNaming` is what reads it. One plan and one filing for every
/// place, so a folder language, an alpha channel and a header image are read
/// the same way wherever they wait.
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
    /// A design tool exports one folder per language. A folder named for a
    /// language says the language of a file whose name leaves it out.
    public static func waiting(in project: Project) -> [ScreenshotFile] {
        let keys: [URLResourceKey] = [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]
        let entries = FileManager.default.enumerator(
            at: url(in: project),
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        )?.compactMap { $0 as? URL } ?? []

        return entries
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

    /// One waiting image, and the set its folder and its name send it to.
    public struct Arrival: Sendable, Hashable, Identifiable {
        public let file: ScreenshotFile

        /// A treatment or a custom product page. Nil for the version, whose
        /// folder is named when the image is filed.
        public let place: LibraryContentPlace?
        public let locale: String
        public let deviceClass: DeviceClass

        /// What the screenshot shows, which is its name without the number,
        /// the device class and the language.
        public let imageName: String

        public var id: URL { file.url }

        public init(
            file: ScreenshotFile,
            place: LibraryContentPlace? = nil,
            locale: String,
            deviceClass: DeviceClass,
            imageName: String
        ) {
            self.file = file
            self.place = place
            self.locale = locale
            self.deviceClass = deviceClass
            self.imageName = imageName
        }
    }

    /// One waiting image this project has nowhere to put, and why.
    public struct Refusal: Sendable, Hashable, Identifiable {
        public let file: ScreenshotFile
        public let reason: String

        /// The treatment or the custom product page the folder names, or nil
        /// for the version and for a folder that names none.
        public let place: LibraryContentPlace?

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
            place: LibraryContentPlace? = nil,
            hasInvalidName: Bool = false,
            unlistedDeviceClass: DeviceClass? = nil,
            hasClearableAlpha: Bool = false
        ) {
            self.file = file
            self.reason = reason
            self.place = place
            self.hasInvalidName = hasInvalidName
            self.unlistedDeviceClass = unlistedDeviceClass
            self.hasClearableAlpha = hasClearableAlpha
        }
    }

    /// The arrivals that go into one set: one place, one language and one
    /// device class.
    public struct Group: Sendable, Hashable {
        public let place: LibraryContentPlace?
        public let locale: String
        public let deviceClass: DeviceClass
        public var arrivals: [Arrival]
    }

    /// What is waiting, split into what can be filed and what cannot.
    public struct Plan: Sendable, Hashable {
        public var arrivals: [Arrival]

        /// Header and search results images, which go to a language and to no
        /// device class.
        public var creative: [CreativeArrival]
        public var refusals: [Refusal]

        public init(arrivals: [Arrival] = [], creative: [CreativeArrival] = [], refusals: [Refusal] = []) {
            self.arrivals = arrivals
            self.creative = creative
            self.refusals = refusals
        }

        public var isEmpty: Bool { hasArrivals == false && refusals.isEmpty }
        public var count: Int { arrivals.count + creative.count + refusals.count }

        /// Whether anything waiting can be filed.
        public var hasArrivals: Bool { arrivals.isEmpty == false || creative.isEmpty == false }

        /// Whether anything waiting goes to the version.
        public var hasVersionArrivals: Bool {
            arrivals.contains { $0.place == nil } || creative.contains { $0.place == nil }
        }

        /// Every waiting image, whatever is going to happen to it.
        public var files: [ScreenshotFile] {
            arrivals.map(\.file) + creative.map(\.file) + refusals.map(\.file)
        }

        /// Whether a waiting file must be renamed before it can be filed.
        public var hasInvalidNames: Bool {
            refusals.contains { $0.hasInvalidName }
        }

        /// The languages of the version the arrivals go to, in the order they
        /// arrived.
        public var locales: [String] {
            var seen: [String] = []
            for arrival in arrivals where arrival.place == nil && seen.contains(arrival.locale) == false {
                seen.append(arrival.locale)
            }
            return seen
        }

        /// The arrivals gathered by set, in the order they arrived.
        ///
        /// One set is written at a time, because the limit of ten screenshots
        /// is counted per set.
        public var groups: [Group] {
            var groups: [Group] = []
            for arrival in arrivals {
                let index = groups.firstIndex {
                    $0.place == arrival.place && $0.locale == arrival.locale && $0.deviceClass == arrival.deviceClass
                }
                if let index {
                    groups[index].arrivals.append(arrival)
                } else {
                    groups.append(Group(
                        place: arrival.place, locale: arrival.locale, deviceClass: arrival.deviceClass,
                        arrivals: [arrival]
                    ))
                }
            }
            return groups
        }
    }
}
