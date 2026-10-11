import ASCKitAPI
import Foundation

public enum XcodeProjectError: ReadableError {
    case unreadable(url: URL)
    case notAProject(url: URL)

    public var localizedStringResource: LocalizedStringResource {
        switch self {
        case let .unreadable(url):
            LocalizedStringResource(
                "Could not read project.xcproj or project.pbxproj in \(url.lastPathComponent).",
                bundle: .here
            )
        case let .notAProject(url):
            LocalizedStringResource("\(url.lastPathComponent) is not an Xcode project this can read.", bundle: .here)
        }
    }
}
