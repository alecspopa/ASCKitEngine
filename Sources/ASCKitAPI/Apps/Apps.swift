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

struct AppStoreVersionWrite: Encodable, Sendable {
    var platform: String?
    var versionString: String?
    var copyright: String?
    var releaseType: String?
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

    /// An app returns more than one appInfo: one live, one editable. The name
    /// and the subtitle can only be written on the editable one, and writing to
    /// the live one answers 409.
    func editableAppInfo(appID: String) async throws -> Resource<AppInfoAttributes>? {
        try await appInfos(appID: appID).first { $0.attributes?.state?.isEditable == true }
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

    /// The version a push should target: the one that still accepts changes.
    /// Prefers an exact version string when the caller names one.
    ///
    /// Every platform, until a caller names one. A Mac app has no IOS version
    /// to find.
    func editableVersion(
        appID: String,
        platform: Platform? = nil,
        versionString: String? = nil
    ) async throws -> Resource<AppStoreVersionAttributes>? {
        let versions = try await appStoreVersions(appID: appID, platform: platform)
        let editable = versions.filter { $0.attributes?.appVersionState?.acceptsTextChanges == true }
        guard let versionString else { return editable.first }
        return editable.first { $0.attributes?.versionString == versionString }
    }

    func createVersion(
        appID: String,
        versionString: String,
        platform: Platform = .ios,
        copyright: String? = nil,
        releaseType: String? = nil
    ) async throws -> Resource<AppStoreVersionAttributes> {
        let body = WriteRequest<AppStoreVersionWrite>(
            data: .init(
                type: "appStoreVersions",
                id: nil,
                attributes: AppStoreVersionWrite(
                    platform: platform.rawValue,
                    versionString: versionString,
                    copyright: copyright,
                    releaseType: releaseType
                ),
                relationships: ["app": RelationshipToOne(type: "apps", id: appID)]
            )
        )
        return try await post("/v1/appStoreVersions", body: body, as: AppStoreVersionAttributes.self)
    }
}
