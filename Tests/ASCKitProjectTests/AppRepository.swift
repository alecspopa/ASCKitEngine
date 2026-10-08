import Foundation
import Testing

/// The ASCKit app repository, when this package sits inside it at
/// `Packages/ASCKitEngine`.
///
/// A few tests read the real Xcode project and the real Icon Composer document
/// there, because Apple never promised to keep those formats. The app is not
/// published with the engine. So in a checkout of the engine alone these tests
/// are skipped, and they say why.
enum AppRepository {
    static let url = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    static var isPresent: Bool {
        FileManager.default.fileExists(atPath: url.appending(path: "ASCKit.xcodeproj").path)
    }

    static let skipReason: Comment = "Needs the ASCKit app repository around this package"
}
