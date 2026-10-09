import Foundation

/// How a straight conversion of the base price compares with what App Store
/// Connect charges.
///
/// Apple's equalized price is not a conversion. It converts at Apple's own
/// rate, then works the local sales tax in, and the two together move it a long
/// way: a euro country is charged about 40 percent more than the base price
/// converted at a market rate, and Colombia about 50 percent more.
///
/// So a curve that multiplies Apple's price cannot mean "a fraction of what the
/// base country pays". It means a fraction of what Apple decided. These ratios
/// bridge the two: multiply Apple's price by the ratio and you have the base
/// price converted at a market rate, in that country's currency, with no tax
/// added on top.
///
/// A ratio above 1.00 is a country where Apple charges *less* than a straight
/// conversion. Qatar, Indonesia, Pakistan and Canada are the notable ones, and
/// a curve using these will raise their price rather than lower it.
///
/// **These go out of date.** That is the cost of the approach, and it is why
/// nothing else here holds an exchange rate. The date is recorded, and `check`
/// warns once a curve's numbers are over a year old.
///
/// Worked out once, by measuring rather than by theory. Every number below is
/// one division: App Store Connect's own equalized price for a real product at
/// a known base, divided into that base converted at a published rate on the
/// same day.
///
/// Measured at one base price, so price point rounding is in these numbers. A
/// country whose ladder has coarse steps carries a little more of it.
enum USDConversion {
    static let provenance = PriceCurve.Provenance(
        source: """
        App Store Connect's own equalized prices for a 14.99 USD base, \
        against exchangerate-api.com's USD rates for the same day.
        """,
        takenOn: "2026-08-30"
    )

    /// Keyed by three-letter country code. A country not here converts at 1.00,
    /// which leaves Apple's own price alone.
    static let ratios: [String: Double] = [
        "AFG": 1.0, "AGO": 1.0, "AIA": 1.0, "ALB": 0.833, "ARE": 0.918, "ARG": 1.0,
        "ARM": 0.833, "ATG": 1.0, "AUS": 0.909, "AUT": 0.718, "AZE": 0.833, "BEL": 0.718,
        "BEN": 0.833, "BFA": 1.0, "BGR": 0.718, "BHR": 1.0, "BHS": 1.0, "BIH": 0.718,
        "BLR": 0.833, "BLZ": 1.0, "BMU": 1.0, "BOL": 1.0, "BRA": 0.775, "BRB": 0.833,
        "BRN": 1.0, "BTN": 1.0, "BWA": 1.0, "CAN": 1.041, "CHE": 0.865, "CHL": 0.771,
        "CHN": 1.032, "CIV": 0.833, "CMR": 0.833, "COD": 1.0, "COG": 1.0, "COL": 0.667,
        "CPV": 1.0, "CRI": 1.0, "CYM": 1.0, "CYP": 0.718, "CZE": 0.781, "DEU": 0.718,
        "DMA": 1.0, "DNK": 0.746, "DOM": 1.0, "DZA": 1.0, "ECU": 1.0, "EGY": 0.942,
        "ESP": 0.718, "EST": 0.718, "FIN": 0.718, "FJI": 1.0, "FRA": 0.718, "FSM": 1.0,
        "GAB": 1.0, "GBR": 0.738, "GEO": 0.833, "GHA": 0.833, "GMB": 1.0, "GNB": 1.0,
        "GRC": 0.718, "GRD": 1.0, "GTM": 1.0, "GUY": 1.0, "HKG": 0.996, "HND": 1.0,
        "HRV": 0.718, "HUN": 0.675, "IDN": 1.069, "IND": 0.956, "IRL": 0.718, "IRQ": 1.0,
        "ISL": 0.833, "ISR": 0.898, "ITA": 0.718, "JAM": 1.0, "JOR": 1.0, "JPN": 0.959,
        "KAZ": 0.774, "KEN": 0.833, "KGZ": 1.0, "KHM": 1.0, "KNA": 1.0, "KOR": 0.826,
        "KWT": 1.0, "LAO": 1.0, "LBN": 1.0, "LBR": 1.0, "LBY": 1.0, "LCA": 1.0, "LKA": 1.0,
        "LTU": 0.718, "LUX": 0.718, "LVA": 0.718, "MAC": 1.0, "MAR": 1.0, "MDA": 0.833,
        "MDG": 1.0, "MDV": 1.0, "MEX": 0.853, "MKD": 1.0, "MLI": 1.0, "MLT": 0.718,
        "MMR": 1.0, "MNE": 0.994, "MNG": 1.0, "MOZ": 1.0, "MRT": 1.0, "MSR": 1.0,
        "MUS": 0.833, "MWI": 1.0, "MYS": 0.863, "NAM": 1.0, "NER": 1.0, "NGA": 0.806,
        "NIC": 1.0, "NLD": 0.718, "NOR": 0.705, "NPL": 0.833, "NRU": 1.0, "NZL": 0.844,
        "OMN": 1.0, "PAK": 1.068, "PAN": 1.0, "PER": 0.719, "PHL": 0.936, "PLW": 1.0,
        "PNG": 1.0, "POL": 0.801, "PRT": 0.718, "PRY": 1.0, "QAT": 1.091, "ROU": 0.846,
        "RUS": 0.998, "RWA": 1.0, "SAU": 0.937, "SEN": 0.833, "SGP": 0.955, "SLB": 1.0,
        "SLE": 1.0, "SLV": 1.0, "SRB": 0.718, "STP": 1.0, "SUR": 1.0, "SVK": 0.718,
        "SVN": 0.718, "SWE": 0.722, "SWZ": 1.0, "SYC": 1.0, "TCA": 1.0, "TCD": 1.0,
        "THA": 0.992, "TJK": 1.0, "TKM": 1.0, "TON": 1.0, "TTO": 1.0, "TUN": 1.0,
        "TUR": 0.904, "TWN": 0.969, "TZA": 0.992, "UGA": 0.833, "UKR": 0.833, "URY": 1.0,
        "USA": 1.0, "UZB": 1.0, "VCT": 1.0, "VEN": 1.0, "VGB": 1.0, "VNM": 0.783,
        "VUT": 1.0, "YEM": 1.0, "ZAF": 0.805, "ZMB": 0.833, "ZWE": 0.833
    ]

    static func ratio(for territory: String) -> Double {
        ratios[territory] ?? 1.0
    }
}
