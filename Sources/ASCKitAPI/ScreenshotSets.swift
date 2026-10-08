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
    public let assetDeliveryState: AssetDeliveryState?
    public let uploadOperations: [UploadOperation]?
    public let imageAsset: ImageAsset?
}

/// Where App Store Connect serves the image it holds. The URL is a template
/// with a width, a height and a file format in it, and it is unauthenticated,
/// so the bearer token must not be attached to it.
public struct ImageAsset: Decodable, Sendable {
    public let templateUrl: String?
    public let width: Int?
    public let height: Int?
}

/// One PUT Apple wants during an upload. The URL is unauthenticated and short
/// lived, so the bearer token must not be attached to it.
public struct UploadOperation: Decodable, Sendable {
    public let method: String
    public let url: String
    public let length: Int
    public let offset: Int
    public let requestHeaders: [Header]

    /// An array of name and value pairs, not a dictionary.
    public struct Header: Decodable, Sendable {
        public let name: String
        public let value: String
    }
}

public extension ASCClient {
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

public extension ASCClient {
    /// Sends one part of an upload where App Store Connect said to send it.
    ///
    /// The address is unauthenticated and short lived. Attaching the bearer
    /// token to it is wrong, so this deliberately does not go through the
    /// normal request path.
    func uploadPart(
        to url: URL,
        method: String,
        headers: [UploadOperation.Header],
        body: Data
    ) async throws {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        for header in headers {
            request.setValue(header.value, forHTTPHeaderField: header.name)
        }

        let (data, response) = try await perform(request)
        guard (200 ..< 300).contains(response.statusCode) else {
            throw ASCError.from(status: response.statusCode, data: data, response: response)
        }
    }
}
