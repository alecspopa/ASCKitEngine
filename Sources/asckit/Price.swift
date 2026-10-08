import ArgumentParser
import ASCKitProject
import Foundation

/// Everything about what an in-app purchase costs.
struct Price: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "price",
        abstract: "Read and set what an in-app purchase costs, country by country.",
        discussion: """
        A price plan is a base price, a curve, and the countries you set by hand. A curve is a \
        multiplier on the price App Store Connect would charge in that country itself, which \
        Apple works out for you and returns already in local currency with tax in it. So a \
        multiplier of 1.00 is exactly Apple's own price, and 0.35 in India is 35 percent of what \
        Apple would charge there.

        Nothing here holds an exchange rate, so nothing here goes out of date when a currency \
        moves.
        """,
        subcommands: [Curves.self, PriceShow.self],
        defaultSubcommand: Curves.self
    )
}

/// The curves ASCKit ships, and what each one is for.
///
/// The discovery command. It needs no key, no network and no project, because
/// choosing a shape is the step before any of that.
struct Curves: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "curves",
        abstract: "List the price curves ASCKit ships.",
        discussion: """
        A curve is named for the shape of its numbers rather than for a company. A file saying \
        a company's name would be a claim about somebody else's prices that ASCKit cannot check \
        and that goes false without notice. A company name still finds the curve with that \
        shape, and what gets written down is the shape.

        Reads nothing and writes nothing.
        """
    )

    @Flag(name: .long, help: "Print every country's multiplier as well.")
    var verbose = false

    func run() throws {
        for curve in PriceCurve.all {
            print(curve.id)
            print("  \(curve.displayName)")
            for line in TextWrapping.lines(curve.summary, at: 74) {
                print("  \(line)")
            }
            if curve.aliases.isEmpty == false {
                print("  Also found as: \(curve.aliases.joined(separator: ", "))")
            }
            print("  \(describe(curve))")
            let source = "From \(curve.provenance.source) Taken \(curve.provenance.takenOn)."
            for line in TextWrapping.lines(source, at: 74) {
                print("  \(line)")
            }
            if verbose { printEveryCountry(of: curve) }
            print("")
        }

        for line in TextWrapping.lines(PriceResolver.roundingRule) {
            print(line)
        }
    }

    /// The shape in one line, so the list can be read without opening anything.
    private func describe(_ curve: PriceCurve) -> String {
        guard curve.bands.isEmpty == false else {
            return "Apple's own price in all \(Territory.all.count) countries."
        }
        // Bands with one multiplier are counted together, so a curve with nine
        // tax steps reads as a range rather than as nine numbers.
        let named = curve.namedTerritories.count
        let untouched = Territory.all.count - named
        let multipliers = curve.bands.map(\.multiplier).sorted()
        guard let lowest = multipliers.first, let highest = multipliers.last else {
            return "Apple's own price in all \(Territory.all.count) countries."
        }
        if curve.bands.count <= 4 {
            let steps = curve.bands
                .map { "\($0.multiplier) in \($0.territories.count)" }
                .joined(separator: ", ")
            return "1.0 in \(untouched) countries, then \(steps)."
        }
        return "1.0 in \(untouched) countries, and \(lowest) to \(highest) in the other \(named)."
    }

    private func printEveryCountry(of curve: PriceCurve) {
        for id in Territory.allIdentifiers {
            guard let territory = Territory.named(id) else { continue }
            let band = curve.band(for: id)?.describedAs ?? "Apple's own price"
            print("    \(id)  \(curve.multiplier(for: id))  \(territory.englishName)  (\(band))")
        }
    }
}
