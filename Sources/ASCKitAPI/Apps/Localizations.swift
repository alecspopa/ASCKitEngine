import Foundation

/// Name, subtitle and the privacy policy. These hang off the app, not off a
/// version, which is why changing a name means a new version once one is live.
public struct AppInfoLocalizationAttributes: Decodable, Sendable {
    public let locale: String?
    public let name: String?
    public let subtitle: String?
    public let privacyPolicyUrl: String?
    public let privacyPolicyText: String?
    public let privacyChoicesUrl: String?
}

struct AppInfoLocalizationWrite: Encodable, Sendable {
    var locale: String?
    var name: String?
    var subtitle: String?
    var privacyPolicyUrl: String?
    var privacyPolicyText: String?
    var privacyChoicesUrl: String?
}

/// Everything else. Note that supportUrl and marketingUrl live here, on the
/// version, while privacyPolicyUrl lives on the app information.
public struct VersionLocalizationAttributes: Decodable, Sendable {
    public let locale: String?
    public let description: String?
    public let keywords: String?
    public let whatsNew: String?
    public let promotionalText: String?
    public let marketingUrl: String?
    public let supportUrl: String?
}

struct VersionLocalizationWrite: Encodable, Sendable {
    var locale: String?
    var description: String?
    var keywords: String?
    var whatsNew: String?
    var promotionalText: String?
    var marketingUrl: String?
    var supportUrl: String?
}

public extension ASCClient {
    // MARK: - App information

    func appInfoLocalizations(
        appInfoID: String
    ) async throws -> [Resource<AppInfoLocalizationAttributes>] {
        try await list("/v1/appInfos/\(appInfoID)/appInfoLocalizations", as: AppInfoLocalizationAttributes.self)
    }

    func createAppInfoLocalization(
        appInfoID: String,
        locale: String,
        name: String? = nil,
        subtitle: String? = nil,
        privacyPolicyUrl: String? = nil
    ) async throws -> Resource<AppInfoLocalizationAttributes> {
        let body = WriteRequest<AppInfoLocalizationWrite>(
            data: .init(
                type: "appInfoLocalizations",
                id: nil,
                attributes: AppInfoLocalizationWrite(
                    locale: locale,
                    name: name,
                    subtitle: subtitle,
                    privacyPolicyUrl: privacyPolicyUrl
                ),
                relationships: ["appInfo": RelationshipToOne(type: "appInfos", id: appInfoID)]
            )
        )
        return try await post("/v1/appInfoLocalizations", body: body, as: AppInfoLocalizationAttributes.self)
    }

    func updateAppInfoLocalization(
        id: String,
        name: String? = nil,
        subtitle: String? = nil,
        privacyPolicyUrl: String? = nil
    ) async throws -> Resource<AppInfoLocalizationAttributes> {
        let body = WriteRequest<AppInfoLocalizationWrite>(
            data: .init(
                type: "appInfoLocalizations",
                id: id,
                attributes: AppInfoLocalizationWrite(
                    name: name,
                    subtitle: subtitle,
                    privacyPolicyUrl: privacyPolicyUrl
                ),
                relationships: nil
            )
        )
        return try await patch("/v1/appInfoLocalizations/\(id)", body: body, as: AppInfoLocalizationAttributes.self)
    }

    // MARK: - Version information

    func versionLocalizations(
        versionID: String
    ) async throws -> [Resource<VersionLocalizationAttributes>] {
        try await list(
            "/v1/appStoreVersions/\(versionID)/appStoreVersionLocalizations",
            as: VersionLocalizationAttributes.self
        )
    }

    func createVersionLocalization(
        versionID: String,
        locale: String,
        description: String? = nil,
        keywords: String? = nil,
        whatsNew: String? = nil,
        promotionalText: String? = nil,
        marketingUrl: String? = nil,
        supportUrl: String? = nil
    ) async throws -> Resource<VersionLocalizationAttributes> {
        let body = WriteRequest<VersionLocalizationWrite>(
            data: .init(
                type: "appStoreVersionLocalizations",
                id: nil,
                attributes: VersionLocalizationWrite(
                    locale: locale,
                    description: description,
                    keywords: keywords,
                    whatsNew: whatsNew,
                    promotionalText: promotionalText,
                    marketingUrl: marketingUrl,
                    supportUrl: supportUrl
                ),
                relationships: [
                    "appStoreVersion": RelationshipToOne(type: "appStoreVersions", id: versionID)
                ]
            )
        )
        return try await post(
            "/v1/appStoreVersionLocalizations",
            body: body,
            as: VersionLocalizationAttributes.self
        )
    }

    func updateVersionLocalization(
        id: String,
        description: String? = nil,
        keywords: String? = nil,
        whatsNew: String? = nil,
        promotionalText: String? = nil,
        marketingUrl: String? = nil,
        supportUrl: String? = nil
    ) async throws -> Resource<VersionLocalizationAttributes> {
        let body = WriteRequest<VersionLocalizationWrite>(
            data: .init(
                type: "appStoreVersionLocalizations",
                id: id,
                attributes: VersionLocalizationWrite(
                    description: description,
                    keywords: keywords,
                    whatsNew: whatsNew,
                    promotionalText: promotionalText,
                    marketingUrl: marketingUrl,
                    supportUrl: supportUrl
                ),
                relationships: nil
            )
        )
        return try await patch(
            "/v1/appStoreVersionLocalizations/\(id)",
            body: body,
            as: VersionLocalizationAttributes.self
        )
    }
}
