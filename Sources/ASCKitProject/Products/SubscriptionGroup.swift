import Foundation

/// One subscription group's words, as `products/groups/<referenceName>.json`.
///
/// App Store Connect will not take a subscription for review until its group
/// has a display name in at least one language.
///
/// The file name is the reference name, the same name each subscription file
/// gives in `subscriptionGroup`. So the file does not hold the name again.
public struct SubscriptionGroup: Codable, Sendable, Hashable, Identifiable {
    public var referenceName: String

    public var status: AppInformation.Status

    /// Keyed by locale. A language that is not here is left alone on App Store
    /// Connect.
    public var localizations: [String: Localization]

    public var id: String { referenceName }

    public struct Localization: Codable, Sendable, Hashable {
        public var name: String?
        public var customAppName: String?

        public init(name: String? = nil, customAppName: String? = nil) {
            self.name = name
            self.customAppName = customAppName
        }

        public subscript(field: GroupField) -> String? {
            get {
                switch field {
                case .name: name
                case .customAppName: customAppName
                }
            }
            set {
                switch field {
                case .name: name = newValue
                case .customAppName: customAppName = newValue
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
        status = try container.decodeIfPresent(
            AppInformation.Status.self, forKey: .status
        ) ?? .draft
        localizations = try container.decodeIfPresent(
            [String: Localization].self, forKey: .localizations
        ) ?? [:]
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(status, forKey: .status)
        try container.encode(localizations, forKey: .localizations)
    }
}
