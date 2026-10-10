import ASCKitAPI
import Foundation

/// Where the screenshots of a place live. The same place type as the previews
/// and the art, so every write names its place the same way.
///
///     versions/<version>/screenshots/<locale>/<device class>/
///     product-page-optimization/<test>/<treatment>/<locale>/<device class>/
///     custom-product-pages/<page>/<locale>/<device class>/
public extension LibraryContentPlace {
    /// Folders beside the language folders that hold something else.
    var reservedFolderNames: Set<String> {
        switch self {
        case .version: []
        case .treatment: [Project.previewsFolderName, CreativeFolder.folderName]
        case .customPage: CustomPageFolders.reservedNames
        }
    }

    /// The screenshots folder below the project folder, as a problem names it.
    func screenshotsPath(config: ProjectConfig) -> String {
        switch self {
        case let .version(version):
            "\(config.versionsPath)/\(version)/\(Project.screenshotsFolderName)"
        case let .treatment(experiment, treatment):
            "\(ExperimentFolders.folderName)/\(experiment)/\(treatment)"
        case let .customPage(page):
            "\(CustomPageFolders.folderName)/\(page)"
        }
    }

    /// The folder of one set below the project folder.
    func screenshotsPath(config: ProjectConfig, locale: String, deviceClassID: String) -> String {
        "\(screenshotsPath(config: config))/\(locale)/\(deviceClassID)"
    }

    /// The previews folder below the project folder, as a problem names it.
    func previewsPath(config: ProjectConfig) -> String {
        switch self {
        case let .version(version): "\(config.versionsPath)/\(version)/\(Project.previewsFolderName)"
        case .treatment, .customPage: "\(screenshotsPath(config: config))/\(Project.previewsFolderName)"
        }
    }
}

public extension ProjectConfig {
    /// The device classes whose screenshots a place takes, in one rule for the
    /// planner, the MCP tools and the window.
    ///
    /// A version takes every device class the project lists. A test takes
    /// those of its platform, and `platform` is nil when the test names none.
    /// A custom product page takes the iPhone and iPad screenshots only: App
    /// Store Connect's reference data names no watch or iMessage group for it.
    func screenshotDeviceClasses(for place: LibraryContentPlace, platform: Platform? = nil) -> [DeviceClass] {
        switch place {
        case .version:
            resolvedDeviceClasses
        case .treatment:
            resolvedDeviceClasses.filter { platform == nil || $0.platform == platform }
        case .customPage:
            resolvedDeviceClasses.filter { $0.platform == .ios && $0.takesPreviews }
        }
    }
}

public extension ExperimentSlot {
    var place: LibraryContentPlace { .treatment(experiment: experiment, treatment: treatment) }
}

public extension CustomPageSlot {
    var place: LibraryContentPlace { .customPage(page) }
}

public extension Project {
    func screenshotsURL(_ place: LibraryContentPlace) -> URL {
        switch place {
        case let .version(version): screenshotsURL(version: version)
        case let .treatment(experiment, treatment): experimentURL(experiment: experiment, treatment: treatment)
        case let .customPage(page): customPageURL(page: page)
        }
    }

    func screenshotsURL(_ place: LibraryContentPlace, locale: String, deviceClassID: String) -> URL {
        screenshotsURL(place).appending(path: locale).appending(path: deviceClassID)
    }

    /// Everything one place holds, read the same way for every place.
    func screenshotFolder(_ place: LibraryContentPlace) -> ScreenshotFolder {
        ScreenshotFolder.load(from: screenshotsURL(place), skipping: place.reservedFolderNames)
    }
}
