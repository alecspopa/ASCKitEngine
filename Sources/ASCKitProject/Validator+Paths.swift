import Foundation

/// Paths in a problem are relative to the project root, so a message reads
/// the same on every machine.
extension Validator {
    func informationPath(_ content: VersionContent, _ locale: String) -> String {
        "\(config.versionsPath)/\(content.versionString)/\(content.informationFolderName)/\(locale).json"
    }

    func screenshotsPath(_ content: VersionContent) -> String {
        "\(config.versionsPath)/\(content.versionString)/\(Project.screenshotsFolderName)"
    }

    func previewsPath(_ content: VersionContent) -> String {
        "\(config.versionsPath)/\(content.versionString)/\(Project.previewsFolderName)"
    }

    func creativePath(_ content: VersionContent) -> String {
        "\(config.versionsPath)/\(content.versionString)/\(CreativeFolder.folderName)"
    }
}
