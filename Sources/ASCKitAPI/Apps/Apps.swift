import Foundation

public struct AppAttributes: Decodable, Sendable {
    public let name: String?
    public let bundleId: String?
    public let sku: String?
    public let primaryLocale: String?
}

public struct AppInfoAttributes: Decodable, Sendable {
    public let state: AppInfoState?
}

public struct AppStoreVersionAttributes: Decodable, Sendable {
    public let platform: Platform?
    public let versionString: String?
    public let appVersionState: AppVersionState?
    public let copyright: String?
    public let releaseType: String?
}

public extension ASCClient {
    /// Nil when no app on the account has that bundle id, which is a different
    /// problem from a key that cannot see it.
    func app(bundleID: String) async throws -> Resource<AppAttributes>? {
        try await list(
            "/v1/apps",
            query: [URLQueryItem(name: "filter[bundleId]", value: bundleID)],
            as: AppAttributes.self
        ).first
    }

    /// The app with that bundle id. Every read of an app starts here.
    func requireApp(bundleID: String) async throws -> Resource<AppAttributes> {
        guard let app = try await app(bundleID: bundleID) else {
            throw AppError.noSuchApp(bundleID: bundleID)
        }
        return app
    }

    func appInfos(appID: String) async throws -> [Resource<AppInfoAttributes>] {
        try await list("/v1/apps/\(appID)/appInfos", as: AppInfoAttributes.self)
    }

    func appStoreVersions(
        appID: String,
        platform: Platform? = nil
    ) async throws -> [Resource<AppStoreVersionAttributes>] {
        var query: [URLQueryItem] = []
        if let platform {
            query.append(URLQueryItem(name: "filter[platform]", value: platform.rawValue))
        }
        return try await list("/v1/apps/\(appID)/appStoreVersions", query: query, as: AppStoreVersionAttributes.self)
    }
}

public enum AppError: ReadableError {
    case noSuchApp(bundleID: String)

    public var localizedStringResource: LocalizedStringResource {
        switch self {
        case let .noSuchApp(bundleID):
            LocalizedStringResource("""
            App Store Connect has no app with the bundle id \(bundleID). Check the id, and \
            check that the key's team owns the app.
            """, bundle: .here)
        }
    }
}
