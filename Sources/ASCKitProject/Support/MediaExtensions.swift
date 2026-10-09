import Foundation

/// The file types the library takes, bare and lower case.
enum MediaExtensions {
    static let video: Set = ["mov", "mp4", "m4v"]
    static let image: Set = ["png", "jpg", "jpeg"]

    /// With the dot, in a fixed order, the way a rule lists them.
    static func dotted(_ extensions: Set<String>) -> [String] {
        extensions.sorted().map { "." + $0 }
    }
}
