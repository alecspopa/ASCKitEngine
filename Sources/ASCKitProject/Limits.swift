import Foundation

/// A field a language writes words into.
///
/// `MetadataField` and `ProductField` are separate enums, because the listing
/// and an in-app purchase hold different fields. This is what the rules about
/// copied words ask them both. See `ProjectConfig.warnsAboutCopiedText`.
public protocol LocalizedField: Sendable {
    /// Whether this language is expected to write the field in its own words,
    /// rather than take the source language's.
    var needsItsOwnWords: Bool { get }
}

/// The two field names both enums say, named once.
///
/// A listing and an in-app purchase both hold a name and a description, and a
/// word translated twice comes back as two words.
private enum Words {
    static let name = LocalizedStringResource("Name", bundle: .here)
    static let description = LocalizedStringResource("Description", bundle: .here)
}

/// The length limits App Store Connect enforces on listing text.
///
/// Every field is counted in characters, keywords included. The belief that
/// keywords are 100 UTF-8 bytes is common and wrong. Counting them that way
/// blocks Japanese and Chinese fields that App Store Connect accepts.
public enum MetadataField: String, Sendable, CaseIterable, Codable {
    case name
    case subtitle
    case keywords
    case promotionalText
    case description
    case whatsNew
    case supportUrl
    case marketingUrl
    case privacyPolicyUrl

    /// What the field is called on screen. The raw value is the key in the
    /// JSON file and in every caller that names a field, so it stays as it is.
    public var displayName: String {
        switch self {
        case .name: String(localized: Words.name)
        case .subtitle: String(localized: "Subtitle", bundle: .module)
        case .keywords: String(localized: "Keywords", bundle: .module)
        case .promotionalText: String(localized: "Promotional Text", bundle: .module)
        case .description: String(localized: Words.description)
        case .whatsNew: String(localized: "What's New", bundle: .module)
        case .supportUrl: String(localized: "Support URL", bundle: .module)
        case .marketingUrl: String(localized: "Marketing URL", bundle: .module)
        case .privacyPolicyUrl: String(localized: "Privacy Policy URL", bundle: .module)
        }
    }

    /// Fields a person writes several lines into, which need a taller box than
    /// a name or a web address does.
    public var isMultiline: Bool {
        self == .description || self == .whatsNew || self == .promotionalText
    }

    /// Whether App Store Connect refuses a submission without it.
    public enum Requirement: Sendable, Hashable {
        /// Needed in every language that gets published.
        case always
        /// Needed once, on the language the listing is written in.
        case sourceLanguageOnly
        /// Apple: "isn't available for the first version of the app but
        /// required for all subsequent versions". Nothing on disk says which
        /// version is the first, so this can only ever be a warning.
        case afterTheFirstVersion
        case never
    }

    public var requirement: Requirement {
        switch self {
        case .name, .description, .keywords, .supportUrl: .always
        case .privacyPolicyUrl: .sourceLanguageOnly
        case .whatsNew: .afterTheFirstVersion
        case .subtitle, .promotionalText, .marketingUrl: .never
        }
    }

    /// Nil where Apple documents no limit.
    public var maximumLength: Int? {
        switch self {
        case .name: 30
        case .subtitle: 30
        case .keywords: 100
        case .promotionalText: 170
        case .description: 4000
        case .whatsNew: 4000
        case .supportUrl, .marketingUrl, .privacyPolicyUrl: nil
        }
    }

    /// The app name has a floor as well as a ceiling.
    public var minimumLength: Int? {
        self == .name ? 2 : nil
    }

    /// Fields that live on `appInfoLocalizations` rather than on the version.
    ///
    /// Note that the privacy policy is here while the support URL is on the
    /// version. Writing either to the wrong resource is a 409, not a bad value.
    public var isAppInfoField: Bool {
        self == .name || self == .subtitle || self == .privacyPolicyUrl
    }

    /// A field holding a web address, which has to be https.
    public var isURL: Bool {
        self == .supportUrl || self == .marketingUrl || self == .privacyPolicyUrl
    }

    /// One emoji is one character, and so is a letter with a combining accent.
    /// That is what App Store Connect counts.
    public func length(of value: String) -> Int {
        value.count
    }
}

/// The length limits App Store Connect enforces on an in-app purchase.
///
/// A separate enum from `MetadataField` rather than more cases on it. That enum
/// drives the language page, every caller that names a field, and the reader
/// that works out which field a 409 refused. A second `name` with a different
/// limit would be wrong in all of them. The two enums live in one file
/// so the two tables are read together.
///
/// The description is 45 characters. That is the number people get wrong, and
/// it is why a purchase needs a counter as much as a listing does.
public enum ProductField: String, Sendable, CaseIterable, Codable {
    case name
    case description

    /// What the field is called on screen. The raw value is the key in the
    /// JSON file and in every caller that names a field, so it stays as it is.
    public var displayName: String {
        switch self {
        case .name: String(localized: Words.name)
        case .description: String(localized: Words.description)
        }
    }

    public var isMultiline: Bool { self == .description }

    public var maximumLength: Int {
        switch self {
        case .name: 30
        case .description: 45
        }
    }

    /// One emoji is one character here too.
    public func length(of value: String) -> Int {
        value.count
    }
}

/// A subscription group's words in one language.
public enum GroupField: String, Sendable, CaseIterable, Codable {
    /// The name a customer reads above the subscriptions in the group.
    case name

    /// A name the store shows instead of the app's own name. Optional.
    case customAppName

    public var displayName: String {
        switch self {
        case .name: String(localized: "Display name", bundle: .module)
        case .customAppName: String(localized: "Custom app name", bundle: .module)
        }
    }

    /// Only the display name is needed. An empty custom app name means the
    /// store shows the app's own name.
    public var isRequired: Bool { self == .name }

    public var maximumLength: Int {
        switch self {
        case .name: 64
        case .customAppName: 30
        }
    }

    public func length(of value: String) -> Int {
        value.count
    }
}

// MARK: - Words a language writes itself

extension MetadataField: LocalizedField {
    /// A web address is the same address in every language, so the source
    /// language's one is the answer. Every other field is words somebody reads.
    public var needsItsOwnWords: Bool { isURL == false }
}

extension GroupField: LocalizedField {
    public var needsItsOwnWords: Bool { true }
}

extension ProductField: LocalizedField {
    /// A purchase holds a name and a description, and both are words somebody
    /// reads.
    public var needsItsOwnWords: Bool { true }
}
