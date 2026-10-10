import ASCKitAPI
import Foundation

extension Inbox {
    /// The treatments and custom product pages a waiting image can go to.
    ///
    /// ASCKit never makes a test, a treatment or a page, so an image in a
    /// folder that names none is refused with the names that do exist.
    struct KnownPlaces: Sendable {
        enum Result {
            /// Nil is the version.
            case found(LibraryContentPlace?)
            case refused(String, LibraryContentPlace?)
        }

        /// The treatment folders of each test folder that takes images.
        var treatments: [String: Set<String>] = [:]
        /// The raw state of each test that takes no images, by folder.
        var lockedTests: [String: String] = [:]
        var pages: Set<String> = []

        /// The languages of each treatment and page, by its place, when the
        /// last read is known.
        var locales: [LibraryContentPlace: [String]] = [:]
        var platforms: [String: Platform] = [:]
        let config: ProjectConfig

        init(project: Project, places: Inbox.Places) {
            config = project.config

            // A folder on disk takes images too, for a project read before.
            for test in DirectoryListing.directories(in: project.experimentsURL) {
                for treatment in DirectoryListing.directories(in: test) {
                    treatments[test.lastPathComponent, default: []].insert(treatment.lastPathComponent)
                }
            }
            for test in places.experiments?.experiments ?? [] {
                guard test.isEditable else {
                    lockedTests[test.folder] = test.state ?? ""
                    continue
                }
                treatments[test.folder, default: []].formUnion(test.treatments.map(\.folder))
                test.platform.map { platforms[test.folder] = Platform(rawValue: $0) }
                for treatment in test.treatments {
                    locales[.treatment(experiment: test.folder, treatment: treatment.folder)] = treatment.locales
                }
            }

            // Only a page that takes changes takes images. With no read, a page
            // folder already on disk does, the way a treatment folder does.
            if let snapshot = places.pages {
                for page in snapshot.pages where page.isEditable {
                    pages.insert(page.folder)
                    locales[.customPage(page.folder)] = page.locales
                }
            } else {
                pages = Set(DirectoryListing.directories(in: project.customPagesURL).map(\.lastPathComponent))
            }
        }

        /// The place the folders under the inbox name. `parts` are the path
        /// below the inbox, the file name last.
        func place(of file: ScreenshotFile, parts: [String]) -> Result {
            switch parts.first {
            case ExperimentFolders.folderName: treatment(of: file, parts: parts)
            case CustomPageFolders.folderName: page(of: file, parts: parts)
            default: .found(nil)
            }
        }

        private func treatment(of file: ScreenshotFile, parts: [String]) -> Result {
            // The tests folder, the test, the treatment, and the file itself.
            guard parts.count >= 4 else {
                return .refused(String(
                    localized: """
                    \(file.fileName) is not in a treatment folder. Put it in \
                    \(ExperimentFolders.folderName)/<test>/<treatment>/.
                    """, bundle: .module
                ), nil)
            }
            let (experiment, treatment) = (parts[1], parts[2])
            let place = LibraryContentPlace.treatment(experiment: experiment, treatment: treatment)

            if let state = lockedTests[experiment] {
                return .refused(String(
                    localized: """
                    The test \(experiment) is \(state) on App Store Connect. Only a test in \
                    Prepare for Submission or Rejected takes images.
                    """, bundle: .module
                ), place)
            }
            guard treatments[experiment]?.contains(treatment) == true else {
                let names = treatments.flatMap { test, items in items.map { "\(test)/\($0)" } }.sorted()
                return .refused(String(
                    localized: """
                    \(experiment)/\(treatment) is not a treatment of a draft test. \
                    Read App Store Connect to make the folders. Known: \(names.joined(separator: ", ")).
                    """, bundle: .module
                ), nil)
            }
            return .found(place)
        }

        private func page(of file: ScreenshotFile, parts: [String]) -> Result {
            // The pages folder, the page, and the file itself.
            guard parts.count >= 3 else {
                return .refused(String(
                    localized: """
                    \(file.fileName) is not in a page folder. Put it in \
                    \(CustomPageFolders.folderName)/<page>/.
                    """, bundle: .module
                ), nil)
            }
            let page = parts[1]
            guard pages.contains(page) else {
                let names = pages.sorted().joined(separator: ", ")
                return .refused(String(
                    localized: """
                    \(page) is not a custom product page that takes changes. \
                    Read App Store Connect to make the folders. Known: \(names).
                    """, bundle: .module
                ), nil)
            }
            return .found(.customPage(page))
        }

        /// Why a treatment or a page takes no image of this language or this
        /// device class, or nil when it takes it.
        func refusal(locale: String, deviceClass: DeviceClass, at place: LibraryContentPlace) -> String? {
            let path = place.screenshotsPath(config: config)
            var platform: Platform?
            if case let .treatment(experiment, _) = place { platform = platforms[experiment] }
            guard config.screenshotDeviceClasses(for: place, platform: platform).contains(deviceClass) else {
                return String(localized: "\(path) takes no \(deviceClass.displayName) screenshots.", bundle: .module)
            }
            if let known = locales[place], known.contains(locale) == false {
                return String(
                    localized: "\(path) has no page for \(locale) on App Store Connect, and ASCKit never makes one.",
                    bundle: .module
                )
            }
            return nil
        }
    }
}
