import Foundation

/// The curves ASCKit ships.
///
/// Four of the five sort the same territories into the same four groups and
/// differ only in the numbers. That is on purpose: the argument between them is
/// about how steep the discount should be, not about which country belongs
/// where, and writing the grouping once means the five cannot drift apart.
///
/// Three of them price from the base price converted at a market rate rather
/// than from what App Store Connect would charge. Apple's price is not a
/// conversion: it converts at Apple's own rate and works the local sales tax in,
/// which puts a euro country about 40 percent above a market conversion. So a
/// curve that multiplied Apple's price could not mean "a fraction of what home
/// pays", which is what these are for. `USDConversion` holds that step.
///
/// `apple-equalized` does not convert, because Apple's price is what it means.
/// `proceeds-parity` uses a different axis again and says so.
///
/// A test checks that every code named in every band is a real territory and
/// that no code is named twice. A typo would otherwise fall through to the base
/// multiplier and become a wrong price nobody notices.
public extension PriceCurve {
    static let all: [PriceCurve] = [
        appleEqualized, tierAnchored, purchasingPower, emergingMarketPush, proceedsParity
    ]

    static let appleEqualized = PriceCurve(
        id: "apple-equalized",
        displayName: String(localized: "Apple equalized", bundle: .module),
        summary: String(localized: """
        Apple's own price everywhere. This is what App Store Connect does when \
        you pick a price and save. Every other curve is measured against it.
        """, bundle: .module),
        aliases: ["automatic", "default"],
        bands: [],
        provenance: IncomeGroup.provenance
    )

    static let tierAnchored = PriceCurve(
        id: "tier-anchored",
        displayName: String(localized: "Two prices", bundle: .module),
        summary: String(localized: """
        The base price, converted, in the higher-income countries, and 60 \
        percent of that everywhere else. The simplest thing that is not the \
        default.
        """, bundle: .module),
        aliases: ["two-price"],
        bands: [
            Band(multiplier: 0.60, describedAs: "everywhere outside the higher-income countries",
                 territories: IncomeGroup.upperMiddle + IncomeGroup.lowerMiddle + IncomeGroup.low)
        ],
        convertsCurrency: true,
        provenance: IncomeGroup.provenance
    )

    static let purchasingPower = PriceCurve(
        id: "purchasing-power",
        displayName: String(localized: "Purchasing power", bundle: .module),
        summary: String(localized: """
        Four steps by income, from the base price converted down to a third \
        of it. The shape a consumer subscription uses when it wants volume in \
        large lower-income markets.
        """, bundle: .module),
        aliases: ["streaming", "netflix", "spotify"],
        bands: [
            Band(multiplier: 0.75, describedAs: "upper-middle income",
                 territories: IncomeGroup.upperMiddle),
            Band(multiplier: 0.55, describedAs: "lower-middle income",
                 territories: IncomeGroup.lowerMiddle),
            Band(multiplier: 0.35, describedAs: "low income",
                 territories: IncomeGroup.low)
        ],
        convertsCurrency: true,
        provenance: IncomeGroup.provenance
    )

    static let emergingMarketPush = PriceCurve(
        id: "emerging-market-push",
        displayName: String(localized: "Emerging market push", bundle: .module),
        summary: String(localized: """
        The same four steps, cut much harder, down to a fifth. For a product \
        that costs near nothing per extra customer. It wants installs and chart \
        position more than revenue per customer.
        """, bundle: .module),
        aliases: ["games", "growth"],
        bands: [
            Band(multiplier: 0.70, describedAs: "upper-middle income",
                 territories: IncomeGroup.upperMiddle),
            Band(multiplier: 0.40, describedAs: "lower-middle income",
                 territories: IncomeGroup.lowerMiddle),
            Band(multiplier: 0.20, describedAs: "low income",
                 territories: IncomeGroup.low)
        ],
        convertsCurrency: true,
        provenance: IncomeGroup.provenance
    )

    /// The one curve that is not about income.
    ///
    /// Apple's equalization makes what the buyer pays comparable across
    /// countries, and the buyer's price includes VAT. So the same equalized
    /// price pays out a quarter less in Hungary than it does in the United
    /// States. This divides that back out, which is what a business wants when
    /// finance needs one net number per seat.
    ///
    /// The numbers are standard VAT rates, so a reduced rate on digital goods
    /// makes this curve slightly too steep in a few places.
    static let proceedsParity = PriceCurve(
        id: "proceeds-parity",
        displayName: String(localized: "Equal proceeds", bundle: .module),
        summary: String(localized: """
        Raises the price where the tax is high, so that what Apple pays you is \
        about the same everywhere. For per-seat and business pricing.
        """, bundle: .module),
        aliases: ["enterprise", "net-parity"],
        bands: [
            Band(multiplier: 1.27, describedAs: "27 percent VAT", territories: ["HUN"]),
            Band(multiplier: 1.26, describedAs: "25 to 26 percent VAT",
                 territories: ["FIN", "DNK", "SWE", "NOR", "HRV", "GRC"]),
            Band(multiplier: 1.23, describedAs: "23 percent VAT",
                 territories: ["IRL", "POL", "PRT"]),
            Band(multiplier: 1.22, describedAs: "21 to 22 percent VAT",
                 territories: ["ITA", "SVN", "BEL", "CZE", "ESP", "LVA", "LTU", "NLD", "ISL"]),
            Band(multiplier: 1.20, describedAs: "20 percent VAT",
                 territories: ["AUT", "BGR", "EST", "FRA", "GBR", "SVK", "MKD", "ALB", "SRB",
                               "MNE", "UKR", "UZB", "ARM", "AZE", "MDA", "BIH"]),
            Band(multiplier: 1.19, describedAs: "19 percent VAT",
                 territories: ["DEU", "CYP", "ROU", "CHL", "COL", "TUR"]),
            Band(multiplier: 1.17, describedAs: "15 to 18 percent VAT",
                 territories: ["ISR", "MLT", "LUX", "ZAF", "MEX", "IND", "NZL", "PER", "DOM",
                               "MAR", "TUN", "KEN", "NGA", "EGY", "PAK", "LKA", "PHL"]),
            Band(multiplier: 1.10, describedAs: "10 to 14 percent VAT",
                 territories: ["AUS", "KOR", "IDN", "VNM", "BRA", "ECU", "PRY", "BOL", "SLV",
                               "GTM", "HND", "NIC", "CRI", "PAN", "JPN", "CHN"]),
            Band(multiplier: 1.05, describedAs: "5 to 9 percent VAT",
                 territories: ["CAN", "SGP", "THA", "TWN", "ARE", "SAU", "BHR", "OMN", "CHE",
                               "MYS", "NPL", "JOR", "LBN"])
        ],
        provenance: Provenance(
            source: "Standard national VAT rates, as published by each tax authority.",
            takenOn: "2026-08-29"
        )
    )
}

// MARK: - The grouping four of the curves share

/// Which income group each territory sits in.
///
/// Broadly the World Bank's four groups, with the small territories the App
/// Store bills in dollars put in the top one. Every territory appears exactly
/// once, and a test proves it, because a code named twice or not at all would
/// become a price nobody chose.
///
/// The top group is not written out. A territory no group names takes the
/// curve's base multiplier, which is 1.00 in every shipped curve, and that is
/// what the top group would have given it anyway.
enum IncomeGroup {
    static let provenance = PriceCurve.Provenance(
        source: """
        World Bank income groups, with the App Store's dollar-billed \
        territories counted as high income.
        """,
        takenOn: "2026-08-29"
    )

    static let high = [
        "AIA", "ARE", "ATG", "AUS", "AUT", "BEL", "BHR", "BHS", "BMU", "BRB", "BRN", "CAN",
        "CHE", "CHL", "CYM", "CYP", "CZE", "DEU", "DNK", "ESP", "EST", "FIN", "FRA", "GBR",
        "GRC", "HKG", "HRV", "HUN", "IRL", "ISL", "ISR", "ITA", "JPN", "KNA", "KOR", "KWT",
        "LTU", "LUX", "LVA", "MAC", "MLT", "MSR", "NLD", "NOR", "NRU", "NZL", "OMN", "PAN",
        "PLW", "POL", "PRT", "QAT", "SAU", "SGP", "SVK", "SVN", "SWE", "SYC", "TCA", "TTO",
        "TWN", "URY", "USA", "VGB"
    ]

    static let upperMiddle = [
        "ALB", "ARG", "ARM", "AZE", "BGR", "BIH", "BLR", "BLZ", "BRA", "BWA", "CHN", "COL",
        "CRI", "DMA", "DOM", "ECU", "FJI", "GAB", "GEO", "GRD", "GTM", "GUY", "IRQ", "JAM",
        "JOR", "KAZ", "LBN", "LBY", "LCA", "MDA", "MDV", "MEX", "MKD", "MNE", "MNG", "MUS",
        "MYS", "NAM", "PER", "PRY", "ROU", "RUS", "SRB", "SUR", "THA", "TKM", "TUR", "VCT",
        "XKS", "ZAF"
    ]

    static let lowerMiddle = [
        "AGO", "BOL", "BTN", "CIV", "CMR", "COG", "CPV", "DZA", "EGY", "FSM", "GHA", "HND",
        "IDN", "IND", "KEN", "KGZ", "KHM", "LAO", "LKA", "MAR", "MMR", "MRT", "NGA", "NIC",
        "NPL", "PAK", "PHL", "PNG", "SEN", "SLB", "SLV", "STP", "SWZ", "TJK", "TON", "TUN",
        "TZA", "UKR", "UZB", "VEN", "VNM", "VUT", "ZMB", "ZWE"
    ]

    static let low = [
        "AFG", "BEN", "BFA", "COD", "GMB", "GNB", "LBR", "MDG", "MLI", "MOZ", "MWI", "NER",
        "RWA", "SLE", "TCD", "UGA", "YEM"
    ]

    /// Every territory this file names, top group included, for the checks.
    static var allNamed: [String] { high + upperMiddle + lowerMiddle + low }
}
