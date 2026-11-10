import Foundation

/// One retention message's words, as `products/retention-messages/<referenceName>.json`.
///
/// App Store Connect shows the message when a subscriber starts to cancel.
/// The file name is the reference name. The image sits beside the file as
/// `<referenceName>.png` or `.jpg`, one for every language.
public struct RetentionMessage: Codable, Sendable, Hashable, Identifiable {
    public var referenceName: String

    public var status: AppInformation.Status

    /// Keyed by locale. A language that is not here is left alone on App Store
    /// Connect.
    public var localizations: [String: Localization]

    public var id: String { referenceName }

    public struct Localization: Codable, Sendable, Hashable {
        public var header: String?
        public var body: String?

        public init(header: String? = nil, body: String? = nil) {
            self.header = header
            self.body = body
        }

        public subscript(field: RetentionField) -> String? {
            get {
                switch field {
                case .header: header
                case .body: body
                }
            }
            set {
                switch field {
                case .header: header = newValue
                case .body: body = newValue
                }
            }
        }
    }

    public init(
        referenceName: String,
        status: AppInformation.Status = .draft,
        localizations: [String: Localization] = [:]
    ) {
        self.referenceName = referenceName
        self.status = status
        self.localizations = localizations
    }

    // MARK: - Reading and writing

    private enum CodingKeys: String, CodingKey {
        case status, localizations
    }

    /// The reference name comes from the file name, so a decoder gives an
    /// empty one and `ProductStore` fills it in.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        referenceName = ""
        status = try container.decodeIfPresent(AppInformation.Status.self, forKey: .status) ?? .draft
        localizations = try container.decodeIfPresent([String: Localization].self, forKey: .localizations) ?? [:]
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(status, forKey: .status)
        try container.encode(localizations, forKey: .localizations)
    }
}

public extension RetentionMessage {
    /// The image files a message folder may hold beside the JSON.
    static let imageExtensions = ["png", "jpg", "jpeg"]

    /// The two sizes App Store Connect takes, from its page on 2026-11-10.
    static let imageSizes: [(width: Int, height: Int)] = [(3840, 2160), (5244, 2950)]
}
