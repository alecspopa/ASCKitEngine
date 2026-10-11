import Foundation

// The old screenshot sets are only read now. App Store Connect moved their
// images into the App Asset Library, and the record learns which asset holds
// which bytes by pairing each old screenshot with the placement in its place.

public struct ScreenshotSetAttributes: Decodable, Sendable {
    public let screenshotDisplayType: ScreenshotDisplayType?
}

public struct ScreenshotAttributes: Decodable, Sendable {
    public let fileSize: Int?
    public let fileName: String?
    public let sourceFileChecksum: String?
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
