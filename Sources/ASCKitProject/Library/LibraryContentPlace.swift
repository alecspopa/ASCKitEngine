import Foundation

/// A version, a treatment of a draft test, or a custom product page. Each
/// holds its previews and its art in the same layout.
public enum LibraryContentPlace: Sendable, Hashable {
    case version(String)
    case treatment(experiment: String, treatment: String)
    /// A page by its folder name.
    case customPage(String)
}

/// Every image of one place, keyed by the slot inside the place.
struct PlaceImages {
    var screenshots: [ScreenshotSlot: [ScreenshotFile]] = [:]
    var previews: [ScreenshotSlot: [PreviewFile]] = [:]
    var creative = CreativeFolder()
    var emptied: Set<ScreenshotSlot> = []
}

public extension Project {
    func previewsURL(_ place: LibraryContentPlace) -> URL {
        switch place {
        case let .version(version):
            previewsURL(version: version)
        case let .treatment(experiment, treatment):
            experimentURL(experiment: experiment, treatment: treatment)
                .appending(path: ExperimentContentStore.previewsFolderName)
        case let .customPage(page):
            customPageURL(page: page).appending(path: Project.previewsFolderName)
        }
    }

    func previewsURL(_ place: LibraryContentPlace, locale: String, deviceClassID: String) -> URL {
        previewsURL(place).appending(path: locale).appending(path: deviceClassID)
    }

    func creativeURL(_ place: LibraryContentPlace) -> URL {
        switch place {
        case let .version(version):
            creativeURL(version: version)
        case let .treatment(experiment, treatment):
            experimentURL(experiment: experiment, treatment: treatment).appending(path: CreativeFolder.folderName)
        case let .customPage(page):
            customPageURL(page: page).appending(path: CreativeFolder.folderName)
        }
    }

    func creativeURL(_ place: LibraryContentPlace, locale: String) -> URL {
        creativeURL(place).appending(path: locale)
    }
}

extension Project {
    /// The screenshots, previews and art of one place, read the same way for
    /// a treatment and a custom page.
    func images(of place: LibraryContentPlace) -> PlaceImages {
        let sets = screenshotFolder(place)
        return PlaceImages(
            screenshots: sets.screenshots,
            previews: PreviewFolder.load(from: previewsURL(place)).previews,
            creative: CreativeFolder.load(from: creativeURL(place)),
            emptied: sets.emptied
        )
    }
}
