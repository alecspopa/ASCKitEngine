import Foundation

// MARK: - What App Store Connect sends

struct RetentionMessageAttributes: Decodable, Sendable {
    let referenceName: String?
}

struct RetentionVersionAttributes: Decodable, Sendable {
    let state: RetentionVersionState?
}

struct RetentionWordsAttributes: Decodable, Sendable {
    let locale: String?
    let header: String?
    let body: String?
}

// MARK: - What a read gives back

/// A retention message with its newest version.
public struct RemoteRetentionMessage: Sendable, Hashable {
    public let id: String
    public let referenceName: String
    public let version: RemoteRetentionVersion?

    public init(id: String, referenceName: String, version: RemoteRetentionVersion?) {
        self.id = id
        self.referenceName = referenceName
        self.version = version
    }
}

public struct RemoteRetentionVersion: Sendable, Hashable {
    public let id: String
    public let state: RetentionVersionState?
    public let words: [String: RemoteRetentionWords]
    public let placementID: String?

    /// The library image the placement shows.
    public let placedAssetID: String?

    public init(
        id: String,
        state: RetentionVersionState?,
        words: [String: RemoteRetentionWords],
        placementID: String?,
        placedAssetID: String? = nil
    ) {
        self.id = id
        self.state = state
        self.words = words
        self.placementID = placementID
        self.placedAssetID = placedAssetID
    }

    /// Only a version that is not yet published takes a change.
    public var acceptsChanges: Bool { state?.isEditable == true }
}

public struct RemoteRetentionWords: Sendable, Hashable {
    public let id: String
    public let header: String?
    public let body: String?

    public init(id: String, header: String?, body: String?) {
        self.id = id
        self.header = header
        self.body = body
    }
}

// MARK: - What a write sends

/// A field left nil is not sent, and stays as it is.
public struct RetentionWordsWrite: Encodable, Sendable, Hashable {
    public var locale: String?
    public var header: String?
    public var body: String?

    public init(locale: String? = nil, header: String? = nil, body: String? = nil) {
        self.locale = locale
        self.header = header
        self.body = body
    }
}

// MARK: - Reading

public extension ASCClient {
    /// Every retention message of the app, each with its newest version and words.
    func retentionMessages(appID: String) async throws -> [RemoteRetentionMessage] {
        let messages = try await list(
            "/v1/apps/\(appID)/retentionMessages", query: [.maxPageSize], as: RetentionMessageAttributes.self
        )
        return try await messages.concurrentMap(limit: 4) { message in
            try await retentionMessage(message)
        }
    }

    private func retentionMessage(_ message: Resource<RetentionMessageAttributes>) async throws -> RemoteRetentionMessage {
        let versions = try await list(
            "/v1/retentionMessages/\(message.id)/versions", query: [.maxPageSize], as: RetentionVersionAttributes.self
        )
        var version: RemoteRetentionVersion?
        if let newest = Self.retentionVersion(in: versions) {
            version = try await retentionVersion(newest)
        }
        return RemoteRetentionMessage(
            id: message.id, referenceName: message.attributes?.referenceName ?? "", version: version
        )
    }

    private func retentionVersion(_ version: Resource<RetentionVersionAttributes>) async throws -> RemoteRetentionVersion {
        async let words = list(
            "/v1/retentionMessageVersions/\(version.id)/localizations", query: [.maxPageSize],
            as: RetentionWordsAttributes.self
        )
        let placement = try await placement(of: version.id)
        var byLocale: [String: RemoteRetentionWords] = [:]
        for row in try await words {
            guard let locale = row.attributes?.locale else { continue }
            byLocale[locale] = RemoteRetentionWords(id: row.id, header: row.attributes?.header, body: row.attributes?.body)
        }
        return RemoteRetentionVersion(
            id: version.id, state: version.attributes?.state, words: byLocale,
            placementID: placement?.id, placedAssetID: placement?.related("image")
        )
    }

    /// `"data": null` when the version has no image.
    private func placement(of versionID: String) async throws -> Resource<NoAttributes>? {
        struct Answer: Decodable { let data: Resource<NoAttributes>? }
        let data = try await send(
            method: HTTPMethod.get,
            url: url(
                "/v1/retentionMessageVersions/\(versionID)/placement",
                query: [URLQueryItem(name: "include", value: "image")]
            ),
            body: nil
        ).0
        do {
            return try JSONDecoder().decode(Answer.self, from: data).data
        } catch {
            throw ASCError.decodingFailed(underlying: error, body: data)
        }
    }

    /// The draft when there is one, else the newest version by state.
    ///
    /// shortcut: the state order stands in for a version number Apple does not
    /// send. Check it against the first message with two versions.
    internal static func retentionVersion(
        in versions: [Resource<RetentionVersionAttributes>]
    ) -> Resource<RetentionVersionAttributes>? {
        versions.max { ($0.attributes?.state?.recency ?? 0) < ($1.attributes?.state?.recency ?? 0) }
    }
}

// MARK: - The bodies a write sends

extension ASCClient {
    /// Built here and nowhere else, so a dry run prints what a real run sends.
    static func retentionWordsBody(versionID: String, words: RetentionWordsWrite) -> WriteRequest<RetentionWordsWrite> {
        .create(
            "retentionMessageLocalizations",
            attributes: words,
            relationships: [
                "retentionMessageVersion": RelationshipToOne(type: "retentionMessageVersions", id: versionID)
            ]
        )
    }

    static func retentionWordsChange(id: String, words: RetentionWordsWrite) -> WriteRequest<RetentionWordsWrite> {
        .update("retentionMessageLocalizations", id: id, attributes: words)
    }
}

// MARK: - Writing

public extension ASCClient {
    /// Adds a language to a version that is not yet published.
    func createRetentionWords(versionID: String, _ words: RetentionWordsWrite) async throws {
        _ = try await create(
            Self.retentionWordsBody(versionID: versionID, words: words), as: RetentionWordsAttributes.self
        )
    }

    func updateRetentionWords(id: String, _ words: RetentionWordsWrite) async throws {
        _ = try await update(Self.retentionWordsChange(id: id, words: words), as: RetentionWordsAttributes.self)
    }
}

/// What a retention write would send, as text to read before it goes.
public enum RetentionWritePreview {
    public static func words(versionID: String, _ words: RetentionWordsWrite) -> String {
        WritePreviewJSON.text(for: ASCClient.retentionWordsBody(versionID: versionID, words: words))
    }

    public static func wordsChange(id: String, _ words: RetentionWordsWrite) -> String {
        WritePreviewJSON.text(for: ASCClient.retentionWordsChange(id: id, words: words))
    }
}
