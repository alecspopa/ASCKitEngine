import Foundation

// The old screenshot sets are only read now. App Store Connect moved their
// images into the App Asset Library, and the record learns which asset holds
// which bytes by pairing each old screenshot with the placement in its place.

struct ScreenshotSetAttributes: Decodable, Sendable {
    let screenshotDisplayType: ScreenshotDisplayType?
}

struct ScreenshotAttributes: Decodable, Sendable {
    let fileSize: Int?
    let fileName: String?
    let sourceFileChecksum: String?
}

extension ASCClient {
    func screenshotSets(
        localizationID: String
    ) async throws -> [Resource<ScreenshotSetAttributes>] {
        try await list(
            "/v1/appStoreVersionLocalizations/\(localizationID)/appScreenshotSets",
            as: ScreenshotSetAttributes.self
        )
    }

    func screenshots(setID: String) async throws -> [Resource<ScreenshotAttributes>] {
        try await list("/v1/appScreenshotSets/\(setID)/appScreenshots", as: ScreenshotAttributes.self)
    }
}
