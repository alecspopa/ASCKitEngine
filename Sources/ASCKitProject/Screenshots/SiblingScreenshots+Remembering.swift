import ASCKitAPI
import Foundation

extension SiblingScreenshots {
    static func remember(
        from donor: String,
        to locale: String,
        deviceClassID: String,
        in project: Project
    ) throws {
        try change(project) { config in
            config.copiesScreenshotsFrom[locale, default: [:]][deviceClassID] = donor

            // The newer export landed in `donor` this time. Two languages that
            // copy each other copy nothing, so the older direction goes.
            if config.copiesScreenshotsFrom[donor]?[deviceClassID] == locale {
                config.copiesScreenshotsFrom[donor]?[deviceClassID] = nil
            }
            if config.copiesScreenshotsFrom[donor]?.isEmpty == true {
                config.copiesScreenshotsFrom[donor] = nil
            }
        }
    }

    /// Takes one copy out of `copiesScreenshotsFrom`, so a new version folder
    /// stops making it. The files stay as they are.
    @discardableResult
    public static func forget(
        locale: String,
        deviceClassID: String,
        in project: Project
    ) throws -> ProjectConfig {
        try change(project) { config in
            config.copiesScreenshotsFrom[locale]?[deviceClassID] = nil
            // The key goes when the last device class does, as it does in
            // `usesSourceScreenshots`.
            if config.copiesScreenshotsFrom[locale]?.isEmpty == true {
                config.copiesScreenshotsFrom[locale] = nil
            }
        }
    }

    /// Reads the configuration file again before writing it.
    ///
    /// A caller that makes several copies holds one read of the folder for all
    /// of them. Writing from that read would keep the last copy and drop the
    /// rest.
    @discardableResult
    private static func change(
        _ project: Project,
        _ body: (inout ProjectConfig) -> Void
    ) throws -> ProjectConfig {
        let before = try Project.load(at: project.configURL).config
        var config = before
        body(&config)
        if config != before { try project.write(config) }
        return config
    }
}
