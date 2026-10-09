import Foundation

/// The state of one version of a custom product page.
///
/// A wrapper around a raw string for the reason `ExperimentState` is one:
/// Apple adds values.
public struct CustomPageVersionState: RawRepresentable, Sendable, Hashable, Codable {
    public let rawValue: String
    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static let prepareForSubmission = Self(rawValue: "PREPARE_FOR_SUBMISSION")
    public static let readyForReview = Self(rawValue: "READY_FOR_REVIEW")
    public static let waitingForReview = Self(rawValue: "WAITING_FOR_REVIEW")
    public static let inReview = Self(rawValue: "IN_REVIEW")
    public static let accepted = Self(rawValue: "ACCEPTED")
    public static let approved = Self(rawValue: "APPROVED")
    public static let replacedWithNewVersion = Self(rawValue: "REPLACED_WITH_NEW_VERSION")
    public static let rejected = Self(rawValue: "REJECTED")

    /// A version nobody has sent to review yet. Only this one takes changes,
    /// the same rule as a draft test.
    public var isEditable: Bool { self == .prepareForSubmission }

    /// Which version of a page to show when it has more than one. A draft
    /// first, because that is the one a person works on. A replaced version
    /// never shows.
    var showOrder: Int? {
        switch self {
        case .prepareForSubmission: 0
        case .rejected: 1
        case .readyForReview, .waitingForReview, .inReview: 2
        case .accepted, .approved: 3
        case .replacedWithNewVersion: nil
        default: 4
        }
    }
}

public struct CustomPageAttributes: Decodable, Sendable {
    public let name: String?
    public let url: String?
    public let visible: Bool?
}

public struct CustomPageVersionAttributes: Decodable, Sendable {
    public let version: String?
    public let state: CustomPageVersionState?
    public let deepLink: String?
}

public struct CustomPageLocalizationAttributes: Decodable, Sendable {
    public let locale: String?
    public let promotionalText: String?
}

struct CustomPageVersionWrite: Encodable, Sendable {
    var deepLink: String?
}

struct CustomPageLocalizationWrite: Encodable, Sendable {
    var promotionalText: String?
}

// MARK: - Calls

public extension ASCClient {
    func customPages(appID: String) async throws -> [Resource<CustomPageAttributes>] {
        try await list(
            "/v1/apps/\(appID)/appCustomProductPages",
            query: [.maxPageSize],
            as: CustomPageAttributes.self
        )
    }

    func customPageVersions(pageID: String) async throws -> [Resource<CustomPageVersionAttributes>] {
        try await list(
            "/v1/appCustomProductPages/\(pageID)/appCustomProductPageVersions",
            as: CustomPageVersionAttributes.self
        )
    }

    func customPageLocalizations(
        versionID: String
    ) async throws -> [Resource<CustomPageLocalizationAttributes>] {
        try await list(
            "/v1/appCustomProductPageVersions/\(versionID)/appCustomProductPageLocalizations",
            as: CustomPageLocalizationAttributes.self
        )
    }

    /// The ids of the keywords linked to one language of a page.
    func customPageKeywordIDs(localizationID: String) async throws -> [String] {
        try await list(
            "/v1/appCustomProductPageLocalizations/\(localizationID)/relationships/searchKeywords",
            query: [.maxPageSize],
            as: NoAttributes.self
        ).map(\.id)
    }

    /// The ids of the keywords a page of this app can use in one language.
    func appKeywordIDs(appID: String, locale: String, platform: Platform = .ios) async throws -> [String] {
        try await list(
            "/v1/apps/\(appID)/searchKeywords",
            query: [
                URLQueryItem(name: "filter[locale]", value: locale),
                URLQueryItem(name: "filter[platform]", value: platform.rawValue),
                .maxPageSize
            ],
            as: NoAttributes.self
        ).map(\.id)
    }

    /// The ids of the keywords of one language of a version.
    func versionKeywordIDs(localizationID: String) async throws -> [String] {
        try await list(
            "/v1/appStoreVersionLocalizations/\(localizationID)/searchKeywords",
            query: [.maxPageSize],
            as: NoAttributes.self
        ).map(\.id)
    }

    func updateCustomPageVersion(id: String, deepLink: String) async throws {
        let body = WriteRequest<CustomPageVersionWrite>(
            data: .init(
                type: "appCustomProductPageVersions",
                id: id,
                attributes: CustomPageVersionWrite(deepLink: deepLink),
                relationships: nil
            )
        )
        _ = try await patch(
            "/v1/appCustomProductPageVersions/\(id)",
            body: body,
            as: CustomPageVersionAttributes.self
        )
    }

    func updateCustomPageLocalization(id: String, promotionalText: String) async throws {
        let body = WriteRequest<CustomPageLocalizationWrite>(
            data: .init(
                type: "appCustomProductPageLocalizations",
                id: id,
                attributes: CustomPageLocalizationWrite(promotionalText: promotionalText),
                relationships: nil
            )
        )
        _ = try await patch(
            "/v1/appCustomProductPageLocalizations/\(id)",
            body: body,
            as: CustomPageLocalizationAttributes.self
        )
    }

    func linkKeywords(_ keywordIDs: [String], localizationID: String) async throws {
        try await addToRelationship(
            Self.keywordsPath(localizationID),
            keywordIDs.map { Identifier(type: "appKeywords", id: $0) }
        )
    }

    func unlinkKeywords(_ keywordIDs: [String], localizationID: String) async throws {
        try await removeFromRelationship(
            Self.keywordsPath(localizationID),
            keywordIDs.map { Identifier(type: "appKeywords", id: $0) }
        )
    }

    private static func keywordsPath(_ localizationID: String) -> String {
        "/v1/appCustomProductPageLocalizations/\(localizationID)/relationships/searchKeywords"
    }
}

// MARK: - What App Store Connect holds

/// The custom product pages of one app, with everything a push needs to write
/// into them.
public struct RemoteCustomPages: Sendable {
    public let appID: String
    public let pages: [RemoteCustomPage]

    /// The keywords a page can use, by language. Read only for the languages
    /// the pages have.
    public let keywords: [String: [String]]

    public init(appID: String, pages: [RemoteCustomPage], keywords: [String: [String]] = [:]) {
        self.appID = appID
        self.pages = pages
        self.keywords = keywords
    }

    public func page(id: String) -> RemoteCustomPage? {
        pages.first { $0.id == id }
    }
}

public struct RemoteCustomPage: Sendable, Identifiable {
    public let id: String
    public let name: String
    public let url: String?
    public let visible: Bool

    /// The version shown and written to. Nil when the page has only replaced
    /// versions, which App Store Connect does not do today.
    public let version: RemoteCustomPageVersion?

    public init(id: String, name: String, url: String?, visible: Bool, version: RemoteCustomPageVersion?) {
        self.id = id
        self.name = name
        self.url = url
        self.visible = visible
        self.version = version
    }

    public var isEditable: Bool { version?.state?.isEditable == true }
}

public struct RemoteCustomPageVersion: Sendable, Identifiable {
    public let id: String
    public let version: String?
    public let state: CustomPageVersionState?
    public let deepLink: String?
    public let localizations: [RemoteCustomPageLocalization]

    public init(
        id: String,
        version: String?,
        state: CustomPageVersionState?,
        deepLink: String?,
        localizations: [RemoteCustomPageLocalization]
    ) {
        self.id = id
        self.version = version
        self.state = state
        self.deepLink = deepLink
        self.localizations = localizations
    }

    public func localization(_ locale: String) -> RemoteCustomPageLocalization? {
        localizations.first { $0.locale == locale }
    }
}

public struct RemoteCustomPageLocalization: Sendable, Identifiable {
    public let id: String
    public let locale: String
    public let promotionalText: String?
    public let keywordIDs: [String]
    /// The library assets placed on this language, in the store's order.
    public let placements: [RemotePlacement]

    public init(
        id: String,
        locale: String,
        promotionalText: String?,
        keywordIDs: [String] = [],
        placements: [RemotePlacement] = []
    ) {
        self.id = id
        self.locale = locale
        self.promotionalText = promotionalText
        self.keywordIDs = keywordIDs
        self.placements = placements
    }
}

// MARK: - The whole read

public extension ASCClient {
    /// Reads the custom product pages of an app: the version of each that
    /// shows, its languages, their keywords and the library assets placed on
    /// them.
    ///
    /// Nothing is made. A page, a version and a language of a page all come
    /// from App Store Connect, and ASCKit only writes into them.
    func customPages(bundleID: String) async throws -> RemoteCustomPages {
        guard let app = try await app(bundleID: bundleID) else {
            throw ListingError.noSuchApp(bundleID: bundleID)
        }

        var pages: [RemoteCustomPage] = []
        for page in try await customPages(appID: app.id) {
            try await pages.append(RemoteCustomPage(
                id: page.id,
                name: page.attributes?.name ?? page.id,
                url: page.attributes?.url,
                visible: page.attributes?.visible ?? false,
                version: readShownVersion(pageID: page.id)
            ))
        }

        let locales = Set(pages.flatMap { $0.version?.localizations.map(\.locale) ?? [] })
        var keywords: [String: [String]] = [:]
        for locale in locales.sorted() {
            keywords[locale] = try await appKeywordIDs(appID: app.id, locale: locale)
        }

        // By name, because App Store Connect answers in no order a person can
        // rely on.
        return RemoteCustomPages(
            appID: app.id,
            pages: pages.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending },
            keywords: keywords
        )
    }

    private func readShownVersion(pageID: String) async throws -> RemoteCustomPageVersion? {
        let versions = try await customPageVersions(pageID: pageID)
        let shown = versions
            .compactMap { version in version.attributes?.state?.showOrder.map { (version, $0) } }
            .min { $0.1 < $1.1 }?.0
        guard let shown else { return nil }

        return try await RemoteCustomPageVersion(
            id: shown.id,
            version: shown.attributes?.version,
            state: shown.attributes?.state,
            deepLink: shown.attributes?.deepLink,
            localizations: readCustomPageLocalizations(versionID: shown.id)
        )
    }

    /// Languages are read together, because a page in eleven languages is
    /// otherwise eleven round trips waiting on each other.
    private func readCustomPageLocalizations(
        versionID: String
    ) async throws -> [RemoteCustomPageLocalization] {
        let resources = try await customPageLocalizations(versionID: versionID)

        let outcomes = await withTaskGroup(
            of: Result<RemoteCustomPageLocalization?, any Error>.self
        ) { group in
            for resource in resources {
                group.addTask {
                    await Self.captured {
                        guard let locale = resource.attributes?.locale else { return nil }
                        async let keywordIDs = customPageKeywordIDs(localizationID: resource.id)
                        async let placements = readPlacements(
                            on: .customProductPageLocalization(id: resource.id), locale: locale
                        )
                        return try await RemoteCustomPageLocalization(
                            id: resource.id,
                            locale: locale,
                            promotionalText: resource.attributes?.promotionalText,
                            keywordIDs: keywordIDs,
                            placements: placements
                        )
                    }
                }
            }
            var collected: [Result<RemoteCustomPageLocalization?, any Error>] = []
            for await outcome in group {
                collected.append(outcome)
            }
            return collected
        }

        return try Self.unwrap(outcomes).compactMap(\.self).sorted { $0.locale < $1.locale }
    }
}
