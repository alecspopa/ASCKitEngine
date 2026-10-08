import Foundation

/// A shape for pricing one product across every country the App Store sells in.
///
/// A curve is a multiplier per territory. It does not hold a price and it does
/// not hold an exchange rate. What it multiplies is the price App Store Connect
/// itself would charge in that territory for the base price you picked, which
/// Apple calls an equalization and returns in local currency with tax already
/// worked in.
///
/// So a multiplier of 1.00 is exactly what Apple would do, and 0.35 in India
/// means 35 percent of what Apple would charge there. That sentence stays true
/// when the rupee moves, which is why no table here ever needs an exchange rate
/// in it.
///
/// A curve is named for the shape of its numbers, never for a company. A file
/// saying `"curve": "netflix"` would be a claim about somebody else's prices
/// that ASCKit cannot check and that goes false without notice. A company name
/// is an alias instead: it finds the curve and is never written down.
public struct PriceCurve: Sendable, Hashable, Identifiable {
    public let id: String
    public let displayName: String

    /// One sentence saying what the curve does and who it suits.
    public let summary: String

    /// Other names that find this curve. Matched without case. Never written
    /// into a file and never printed as the curve's own name.
    public let aliases: [String]

    /// The multiplier for a territory no band names.
    ///
    /// Always 1.00 in every shipped curve. A territory nobody thought about
    /// gets Apple's own price, which is the answer that cannot quietly lose
    /// money or quietly overcharge.
    public let baseMultiplier: Double

    public let bands: [Band]

    /// Whether the curve prices from the base price converted at a market rate
    /// rather than from what App Store Connect would charge.
    ///
    /// Apple's price is not a conversion: it converts at Apple's own rate and
    /// then works the local sales tax in, which puts a euro country about 40
    /// percent above the base price converted at a market rate. So a curve that
    /// multiplies Apple's price cannot mean "a fraction of what home pays". One
    /// that converts first can.
    ///
    /// The cost is that the conversion goes out of date, which is why
    /// `apple-equalized` does not do it and neither does `proceeds-parity`.
    public let convertsCurrency: Bool

    public let provenance: Provenance

    public struct Band: Sendable, Hashable {
        public let multiplier: Double

        /// What this band is, so a person reading the plan knows why a country
        /// is in it.
        public let describedAs: String

        public let territories: [String]

        public init(multiplier: Double, describedAs: String, territories: [String]) {
            self.multiplier = multiplier
            self.describedAs = describedAs
            self.territories = territories
        }
    }

    /// Where the numbers came from and when, so a stale table can say so
    /// instead of being trusted forever.
    public struct Provenance: Sendable, Hashable {
        public let source: String

        /// `2026-08-29`. A plain string, because it is a fact about the table
        /// rather than a moment in this program's life.
        public let takenOn: String

        public init(source: String, takenOn: String) {
            self.source = source
            self.takenOn = takenOn
        }
    }

    public init(
        id: String,
        displayName: String,
        summary: String,
        aliases: [String] = [],
        baseMultiplier: Double = 1.0,
        bands: [Band],
        convertsCurrency: Bool = false,
        provenance: Provenance
    ) {
        self.convertsCurrency = convertsCurrency
        self.id = id
        self.displayName = displayName
        self.summary = summary
        self.aliases = aliases
        self.baseMultiplier = baseMultiplier
        self.bands = bands
        self.provenance = provenance
    }
}

public extension PriceCurve {
    /// What to multiply this territory's equalized price by.
    ///
    /// On a converting curve this is two things at once: the step that undoes
    /// Apple's conversion and tax, and the band's own discount. They are worked
    /// out together because only their product ever leaves this method, and
    /// keeping them apart would let a caller apply one and forget the other.
    func multiplier(for territoryID: String) -> Double {
        let banded = bandsByTerritory[territoryID]?.multiplier ?? baseMultiplier
        guard convertsCurrency else { return banded }
        return USDConversion.ratio(for: territoryID) * banded
    }

    /// The band's own number, without the conversion. For a plan that wants to
    /// say which band a country is in rather than what it costs.
    func bandMultiplier(for territoryID: String) -> Double {
        bandsByTerritory[territoryID]?.multiplier ?? baseMultiplier
    }

    /// The band a territory falls in, or nil when no band names it.
    func band(for territoryID: String) -> Band? {
        bandsByTerritory[territoryID]
    }

    /// Why a country pays what it pays, for a plan somebody reads.
    ///
    /// A country in no band still has a reason on a converting curve: the
    /// conversion moved it. Saying nothing there leaves half the rows of a
    /// four-band curve unexplained, because the top band is the one that is not
    /// written out.
    func reason(for territoryID: String) -> String? {
        if let band = band(for: territoryID) { return band.describedAs }
        return convertsCurrency ? "the base price converted" : nil
    }

    /// Every territory named across the bands. A territory named twice appears
    /// twice, which is what lets a test find the mistake.
    var namedTerritories: [String] {
        bands.flatMap(\.territories)
    }

    private var bandsByTerritory: [String: Band] {
        var table: [String: Band] = [:]
        for band in bands {
            for territory in band.territories where table[territory] == nil {
                table[territory] = band
            }
        }
        return table
    }
}

// MARK: - Finding one

public extension PriceCurve {
    private static let byID: [String: PriceCurve] = Dictionary(
        uniqueKeysWithValues: all.map { ($0.id, $0) }
    )

    private static let byAlias: [String: PriceCurve] = {
        var table: [String: PriceCurve] = [:]
        for curve in all {
            for alias in curve.aliases {
                table[alias.lowercased()] = curve
            }
        }
        return table
    }()

    /// The curve with this name, whether the name is the identifier or an
    /// alias. `netflix` answers `purchasing-power`.
    static func named(_ name: String) -> PriceCurve? {
        let wanted = name.lowercased()
        return byID[wanted] ?? byAlias[wanted]
    }

    static func isKnown(_ name: String) -> Bool {
        named(name) != nil
    }

    /// Every identifier, for a message that has to say what the choices are.
    static var allIdentifiers: [String] { all.map(\.id) }
}
