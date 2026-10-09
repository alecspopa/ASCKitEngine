import Foundation

/// One language's listing text, as `version-data/<locale>.json`.
public struct AppInformation: Codable, Sendable, Hashable, Identifiable {
    /// How far along a translation is.
    ///
    /// A plain text file has nowhere to put this, which is the reason the copy
    /// is one structured file per language rather than one file per field.
    public enum Status: String, Codable, Sendable, CaseIterable {
        /// Started, not finished. Never published.
        case draft
        /// Written by a machine and not yet read by a person. Never published.
        case needsHuman = "needs_human"
        /// A machine wrote it, checked its own work, and stands behind it.
        /// Publishes. Kept apart from `approved` so the file says who signed
        /// it off, which is the question somebody asks of a listing that went
        /// out wrong.
        case aiApproved = "ai_approved"
        /// A person read it. Publishes. Only a person sets this one.
        case approved

        public var canPublish: Bool { self == .approved || self == .aiApproved }
    }

    public var locale: String
    public var status: Status

    public var fields: Fields

    public var id: String { locale }

    public struct Fields: Codable, Sendable, Hashable {
        public var name: String?
        public var subtitle: String?
        public var keywords: String?
        public var promotionalText: String?
        public var description: String?
        public var whatsNew: String?
        public var supportUrl: String?
        public var marketingUrl: String?
        public var privacyPolicyUrl: String?

        public init(
            name: String? = nil,
            subtitle: String? = nil,
            keywords: String? = nil,
            promotionalText: String? = nil,
            description: String? = nil,
            whatsNew: String? = nil,
            supportUrl: String? = nil,
            marketingUrl: String? = nil,
            privacyPolicyUrl: String? = nil
        ) {
            self.name = name
            self.subtitle = subtitle
            self.keywords = keywords
            self.promotionalText = promotionalText
            self.description = description
            self.whatsNew = whatsNew
            self.supportUrl = supportUrl
            self.marketingUrl = marketingUrl
            self.privacyPolicyUrl = privacyPolicyUrl
        }

        public subscript(field: MetadataField) -> String? {
            get {
                switch field {
                case .name: name
                case .subtitle: subtitle
                case .keywords: keywords
                case .promotionalText: promotionalText
                case .description: description
                case .whatsNew: whatsNew
                case .supportUrl: supportUrl
                case .marketingUrl: marketingUrl
                case .privacyPolicyUrl: privacyPolicyUrl
                }
            }
            set {
                switch field {
                case .name: name = newValue
                case .subtitle: subtitle = newValue
                case .keywords: keywords = newValue
                case .promotionalText: promotionalText = newValue
                case .description: description = newValue
                case .whatsNew: whatsNew = newValue
                case .supportUrl: supportUrl = newValue
                case .marketingUrl: marketingUrl = newValue
                case .privacyPolicyUrl: privacyPolicyUrl = newValue
                }
            }
        }

        /// Only the fields this language actually sets. A field with no value
        /// is left alone on App Store Connect rather than blanked.
        public var presentFields: [MetadataField] {
            MetadataField.allCases.filter { self[$0] != nil }
        }
    }

    public init(
        locale: String,
        status: Status = .draft,
        fields: Fields = Fields()
    ) {
        self.locale = locale
        self.status = status
        self.fields = fields
    }
}
