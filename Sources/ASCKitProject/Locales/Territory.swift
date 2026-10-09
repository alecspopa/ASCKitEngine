import Foundation

/// The countries and regions the App Store sells in, as App Store Connect
/// names them.
///
/// The identifier is the ISO-3166 alpha-3 code, `USA` and `DEU`, which is what
/// `/v1/territories` returns and what a price relates to. It is not the
/// two-letter code a locale uses and it is not the currency code, and the three
/// are easy to confuse: `CHE` is Switzerland and `CHF` is its currency.
///
/// The two-letter code is carried beside it so a test can check every row
/// against `Locale.Region`. A wrong code here would become a wrong price.
///
/// This table exists so `asckit check` works with no network and no key. App
/// Store Connect is the authority, not this file: `asckit pull --products`
/// reads `/v1/territories` and reports every territory the two disagree about,
/// in either direction. A territory Apple adds is a warning, not a refusal.
///
/// No name here. `Locale` already holds the name for every two-letter code, in
/// every language, so writing it out again would only make something to get
/// wrong.
///
/// The currency is here, because `Locale` gives the wrong one for about 100
/// territories. App Store Connect bills most of Africa, Central Asia and the
/// Caribbean in USD, and Serbia and Bosnia in EUR. A price point from Apple
/// carries no currency, so this table is the only place a price gets one.
public struct Territory: Sendable, Hashable, Identifiable, Codable {
    /// The ISO-3166 alpha-3 code, which is the App Store Connect identifier.
    public let id: String

    /// The ISO-3166 alpha-2 code, for `Locale` and for a flag.
    public let regionCode: String

    /// The ISO-4217 code App Store Connect bills in.
    public let currency: String

    public init(id: String, regionCode: String, currency: String) {
        self.id = id
        self.regionCode = regionCode
        self.currency = currency
    }

    /// What to call this territory on screen, in the reader's own language.
    public func name(in locale: Locale = .current) -> String {
        locale.localizedString(forRegionCode: regionCode) ?? id
    }

    /// The English name, for a message that has to read the same everywhere,
    /// such as a plan somebody pastes into a bug report.
    public var englishName: String {
        name(in: Locale(identifier: "en_US"))
    }
}

public extension Territory {
    static let all: [Territory] = [
        Territory(id: "AFG", regionCode: "AF", currency: "USD"),
        Territory(id: "AGO", regionCode: "AO", currency: "USD"),
        Territory(id: "AIA", regionCode: "AI", currency: "USD"),
        Territory(id: "ALB", regionCode: "AL", currency: "USD"),
        Territory(id: "ARE", regionCode: "AE", currency: "AED"),
        Territory(id: "ARG", regionCode: "AR", currency: "USD"),
        Territory(id: "ARM", regionCode: "AM", currency: "USD"),
        Territory(id: "ATG", regionCode: "AG", currency: "USD"),
        Territory(id: "AUS", regionCode: "AU", currency: "AUD"),
        Territory(id: "AUT", regionCode: "AT", currency: "EUR"),
        Territory(id: "AZE", regionCode: "AZ", currency: "USD"),
        Territory(id: "BEL", regionCode: "BE", currency: "EUR"),
        Territory(id: "BEN", regionCode: "BJ", currency: "USD"),
        Territory(id: "BFA", regionCode: "BF", currency: "USD"),
        Territory(id: "BGR", regionCode: "BG", currency: "EUR"),
        Territory(id: "BHR", regionCode: "BH", currency: "USD"),
        Territory(id: "BHS", regionCode: "BS", currency: "USD"),
        Territory(id: "BIH", regionCode: "BA", currency: "EUR"),
        Territory(id: "BLR", regionCode: "BY", currency: "USD"),
        Territory(id: "BLZ", regionCode: "BZ", currency: "USD"),
        Territory(id: "BMU", regionCode: "BM", currency: "USD"),
        Territory(id: "BOL", regionCode: "BO", currency: "USD"),
        Territory(id: "BRA", regionCode: "BR", currency: "BRL"),
        Territory(id: "BRB", regionCode: "BB", currency: "USD"),
        Territory(id: "BRN", regionCode: "BN", currency: "USD"),
        Territory(id: "BTN", regionCode: "BT", currency: "USD"),
        Territory(id: "BWA", regionCode: "BW", currency: "USD"),
        Territory(id: "CAN", regionCode: "CA", currency: "CAD"),
        Territory(id: "CHE", regionCode: "CH", currency: "CHF"),
        Territory(id: "CHL", regionCode: "CL", currency: "CLP"),
        Territory(id: "CHN", regionCode: "CN", currency: "CNY"),
        Territory(id: "CIV", regionCode: "CI", currency: "USD"),
        Territory(id: "CMR", regionCode: "CM", currency: "USD"),
        Territory(id: "COD", regionCode: "CD", currency: "USD"),
        Territory(id: "COG", regionCode: "CG", currency: "USD"),
        Territory(id: "COL", regionCode: "CO", currency: "COP"),
        Territory(id: "CPV", regionCode: "CV", currency: "USD"),
        Territory(id: "CRI", regionCode: "CR", currency: "USD"),
        Territory(id: "CYM", regionCode: "KY", currency: "USD"),
        Territory(id: "CYP", regionCode: "CY", currency: "EUR"),
        Territory(id: "CZE", regionCode: "CZ", currency: "CZK"),
        Territory(id: "DEU", regionCode: "DE", currency: "EUR"),
        Territory(id: "DMA", regionCode: "DM", currency: "USD"),
        Territory(id: "DNK", regionCode: "DK", currency: "DKK"),
        Territory(id: "DOM", regionCode: "DO", currency: "USD"),
        Territory(id: "DZA", regionCode: "DZ", currency: "USD"),
        Territory(id: "ECU", regionCode: "EC", currency: "USD"),
        Territory(id: "EGY", regionCode: "EG", currency: "EGP"),
        Territory(id: "ESP", regionCode: "ES", currency: "EUR"),
        Territory(id: "EST", regionCode: "EE", currency: "EUR"),
        Territory(id: "FIN", regionCode: "FI", currency: "EUR"),
        Territory(id: "FJI", regionCode: "FJ", currency: "USD"),
        Territory(id: "FRA", regionCode: "FR", currency: "EUR"),
        Territory(id: "FSM", regionCode: "FM", currency: "USD"),
        Territory(id: "GAB", regionCode: "GA", currency: "USD"),
        Territory(id: "GBR", regionCode: "GB", currency: "GBP"),
        Territory(id: "GEO", regionCode: "GE", currency: "USD"),
        Territory(id: "GHA", regionCode: "GH", currency: "USD"),
        Territory(id: "GMB", regionCode: "GM", currency: "USD"),
        Territory(id: "GNB", regionCode: "GW", currency: "USD"),
        Territory(id: "GRC", regionCode: "GR", currency: "EUR"),
        Territory(id: "GRD", regionCode: "GD", currency: "USD"),
        Territory(id: "GTM", regionCode: "GT", currency: "USD"),
        Territory(id: "GUY", regionCode: "GY", currency: "USD"),
        Territory(id: "HKG", regionCode: "HK", currency: "HKD"),
        Territory(id: "HND", regionCode: "HN", currency: "USD"),
        Territory(id: "HRV", regionCode: "HR", currency: "EUR"),
        Territory(id: "HUN", regionCode: "HU", currency: "HUF"),
        Territory(id: "IDN", regionCode: "ID", currency: "IDR"),
        Territory(id: "IND", regionCode: "IN", currency: "INR"),
        Territory(id: "IRL", regionCode: "IE", currency: "EUR"),
        Territory(id: "IRQ", regionCode: "IQ", currency: "USD"),
        Territory(id: "ISL", regionCode: "IS", currency: "USD"),
        Territory(id: "ISR", regionCode: "IL", currency: "ILS"),
        Territory(id: "ITA", regionCode: "IT", currency: "EUR"),
        Territory(id: "JAM", regionCode: "JM", currency: "USD"),
        Territory(id: "JOR", regionCode: "JO", currency: "USD"),
        Territory(id: "JPN", regionCode: "JP", currency: "JPY"),
        Territory(id: "KAZ", regionCode: "KZ", currency: "KZT"),
        Territory(id: "KEN", regionCode: "KE", currency: "USD"),
        Territory(id: "KGZ", regionCode: "KG", currency: "USD"),
        Territory(id: "KHM", regionCode: "KH", currency: "USD"),
        Territory(id: "KNA", regionCode: "KN", currency: "USD"),
        Territory(id: "KOR", regionCode: "KR", currency: "KRW"),
        Territory(id: "KWT", regionCode: "KW", currency: "USD"),
        Territory(id: "LAO", regionCode: "LA", currency: "USD"),
        Territory(id: "LBN", regionCode: "LB", currency: "USD"),
        Territory(id: "LBR", regionCode: "LR", currency: "USD"),
        Territory(id: "LBY", regionCode: "LY", currency: "USD"),
        Territory(id: "LCA", regionCode: "LC", currency: "USD"),
        Territory(id: "LKA", regionCode: "LK", currency: "USD"),
        Territory(id: "LTU", regionCode: "LT", currency: "EUR"),
        Territory(id: "LUX", regionCode: "LU", currency: "EUR"),
        Territory(id: "LVA", regionCode: "LV", currency: "EUR"),
        Territory(id: "MAC", regionCode: "MO", currency: "USD"),
        Territory(id: "MAR", regionCode: "MA", currency: "USD"),
        Territory(id: "MDA", regionCode: "MD", currency: "USD"),
        Territory(id: "MDG", regionCode: "MG", currency: "USD"),
        Territory(id: "MDV", regionCode: "MV", currency: "USD"),
        Territory(id: "MEX", regionCode: "MX", currency: "MXN"),
        Territory(id: "MKD", regionCode: "MK", currency: "USD"),
        Territory(id: "MLI", regionCode: "ML", currency: "USD"),
        Territory(id: "MLT", regionCode: "MT", currency: "EUR"),
        Territory(id: "MMR", regionCode: "MM", currency: "USD"),
        Territory(id: "MNE", regionCode: "ME", currency: "EUR"),
        Territory(id: "MNG", regionCode: "MN", currency: "USD"),
        Territory(id: "MOZ", regionCode: "MZ", currency: "USD"),
        Territory(id: "MRT", regionCode: "MR", currency: "USD"),
        Territory(id: "MSR", regionCode: "MS", currency: "USD"),
        Territory(id: "MUS", regionCode: "MU", currency: "USD"),
        Territory(id: "MWI", regionCode: "MW", currency: "USD"),
        Territory(id: "MYS", regionCode: "MY", currency: "MYR"),
        Territory(id: "NAM", regionCode: "NA", currency: "USD"),
        Territory(id: "NER", regionCode: "NE", currency: "USD"),
        Territory(id: "NGA", regionCode: "NG", currency: "NGN"),
        Territory(id: "NIC", regionCode: "NI", currency: "USD"),
        Territory(id: "NLD", regionCode: "NL", currency: "EUR"),
        Territory(id: "NOR", regionCode: "NO", currency: "NOK"),
        Territory(id: "NPL", regionCode: "NP", currency: "USD"),
        Territory(id: "NRU", regionCode: "NR", currency: "USD"),
        Territory(id: "NZL", regionCode: "NZ", currency: "NZD"),
        Territory(id: "OMN", regionCode: "OM", currency: "USD"),
        Territory(id: "PAK", regionCode: "PK", currency: "PKR"),
        Territory(id: "PAN", regionCode: "PA", currency: "USD"),
        Territory(id: "PER", regionCode: "PE", currency: "PEN"),
        Territory(id: "PHL", regionCode: "PH", currency: "PHP"),
        Territory(id: "PLW", regionCode: "PW", currency: "USD"),
        Territory(id: "PNG", regionCode: "PG", currency: "USD"),
        Territory(id: "POL", regionCode: "PL", currency: "PLN"),
        Territory(id: "PRT", regionCode: "PT", currency: "EUR"),
        Territory(id: "PRY", regionCode: "PY", currency: "USD"),
        Territory(id: "QAT", regionCode: "QA", currency: "QAR"),
        Territory(id: "ROU", regionCode: "RO", currency: "RON"),
        Territory(id: "RUS", regionCode: "RU", currency: "RUB"),
        Territory(id: "RWA", regionCode: "RW", currency: "USD"),
        Territory(id: "SAU", regionCode: "SA", currency: "SAR"),
        Territory(id: "SEN", regionCode: "SN", currency: "USD"),
        Territory(id: "SGP", regionCode: "SG", currency: "SGD"),
        Territory(id: "SLB", regionCode: "SB", currency: "USD"),
        Territory(id: "SLE", regionCode: "SL", currency: "USD"),
        Territory(id: "SLV", regionCode: "SV", currency: "USD"),
        Territory(id: "SRB", regionCode: "RS", currency: "EUR"),
        Territory(id: "STP", regionCode: "ST", currency: "USD"),
        Territory(id: "SUR", regionCode: "SR", currency: "USD"),
        Territory(id: "SVK", regionCode: "SK", currency: "EUR"),
        Territory(id: "SVN", regionCode: "SI", currency: "EUR"),
        Territory(id: "SWE", regionCode: "SE", currency: "SEK"),
        Territory(id: "SWZ", regionCode: "SZ", currency: "USD"),
        Territory(id: "SYC", regionCode: "SC", currency: "USD"),
        Territory(id: "TCA", regionCode: "TC", currency: "USD"),
        Territory(id: "TCD", regionCode: "TD", currency: "USD"),
        Territory(id: "THA", regionCode: "TH", currency: "THB"),
        Territory(id: "TJK", regionCode: "TJ", currency: "USD"),
        Territory(id: "TKM", regionCode: "TM", currency: "USD"),
        Territory(id: "TON", regionCode: "TO", currency: "USD"),
        Territory(id: "TTO", regionCode: "TT", currency: "USD"),
        Territory(id: "TUN", regionCode: "TN", currency: "USD"),
        Territory(id: "TUR", regionCode: "TR", currency: "TRY"),
        Territory(id: "TWN", regionCode: "TW", currency: "TWD"),
        Territory(id: "TZA", regionCode: "TZ", currency: "TZS"),
        Territory(id: "UGA", regionCode: "UG", currency: "USD"),
        Territory(id: "UKR", regionCode: "UA", currency: "USD"),
        Territory(id: "URY", regionCode: "UY", currency: "USD"),
        Territory(id: "USA", regionCode: "US", currency: "USD"),
        Territory(id: "UZB", regionCode: "UZ", currency: "USD"),
        Territory(id: "VCT", regionCode: "VC", currency: "USD"),
        Territory(id: "VEN", regionCode: "VE", currency: "USD"),
        Territory(id: "VGB", regionCode: "VG", currency: "USD"),
        Territory(id: "VNM", regionCode: "VN", currency: "VND"),
        Territory(id: "VUT", regionCode: "VU", currency: "USD"),
        Territory(id: "XKS", regionCode: "XK", currency: "EUR"),
        Territory(id: "YEM", regionCode: "YE", currency: "USD"),
        Territory(id: "ZAF", regionCode: "ZA", currency: "ZAR"),
        Territory(id: "ZMB", regionCode: "ZM", currency: "USD"),
        Territory(id: "ZWE", regionCode: "ZW", currency: "USD")
    ]

    /// Every identifier, in the order the table lists them, which is alphabetical.
    static var allIdentifiers: [String] { all.map(\.id) }

    private static let byID: [String: Territory] = Dictionary(
        uniqueKeysWithValues: all.map { ($0.id, $0) }
    )

    static func named(_ id: String) -> Territory? {
        byID[id]
    }

    static func isKnown(_ id: String) -> Bool {
        byID[id] != nil
    }

    /// The identifier somebody probably meant, so a refusal helps rather than
    /// only saying no.
    ///
    /// Answers a case difference, and a two-letter code written where a
    /// three-letter one belongs. `us` suggests `USA`, and so does `US`.
    static func suggestion(for id: String) -> String? {
        if isKnown(id) { return nil }
        let wanted = id.uppercased()
        if let match = byID[wanted] { return match.id }
        if wanted.count == 2, let match = all.first(where: { $0.regionCode == wanted }) {
            return match.id
        }
        return nil
    }
}
