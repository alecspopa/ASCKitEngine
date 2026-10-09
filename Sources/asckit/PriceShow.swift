import ArgumentParser
import ASCKitAPI
import ASCKitProject
import Foundation

/// What one in-app purchase costs, and what each curve would make it cost.
///
/// Reads both sides and writes nothing, on App Store Connect or on disk. This
/// is the command for deciding, before anything is decided.
struct PriceShow: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "show",
        abstract: "Show what a product costs now, and what each curve would make it cost.",
        discussion: """
        With no --curve it compares every curve ASCKit ships, so you can see the choice rather \
        than guess at it.

        With --curve it prints the whole table for that one, country by country.

        The base price is what the product costs in the base country today, unless --base says \
        otherwise. A curve multiplies the price App Store Connect would charge in each country \
        for that base, which Apple works out and ASCKit reads.

        Writes nothing.
        """
    )

    /// Declared before the shared options, because those hold a positional
    /// folder argument and whichever is declared first is read first.
    @Argument(help: "The product id, as your app asks the store for it.")
    var productID: String

    @OptionGroup var options: ProjectOptions

    @Option(name: .long, help: "One curve, printed country by country.")
    var curve: String?

    @Option(name: .long, help: "The price to work from. Defaults to what the base country pays.")
    var base: String?

    @Option(name: .long, help: "The country the base price is in.")
    var baseTerritory: String?

    @Option(
        name: .long,
        help: "Only these countries, as three-letter codes separated by commas."
    )
    var territory: String?

    func run() async throws {
        let project = try options.loadProject()
        let client = try makeClient(for: project)

        let remote = try await client.products(bundleID: project.config.bundleID, includeWords: false)
        guard let product = remote.byProductID[productID] else {
            print("App Store Connect has no in-app purchase called \(productID).")
            print("It has: \(remote.products.map(\.productID).joined(separator: ", "))")
            throw ExitCode.failure
        }

        let home = baseTerritory ?? project.config.baseTerritory
        let wanted = territory?.split(separator: ",").map(String.init)
            ?? Territory.allIdentifiers

        print("\(productID), \(product.kind), \(product.state ?? unknownState)")
        print("Reading every price the store will sell this at. This takes a moment.")

        // The ladder comes first, with no base price, so what the store charges
        // today arrives even when nobody has said what to work from.
        let ladder = try await client.prices(
            for: product,
            baseTerritory: home,
            baseAmount: base ?? "",
            territories: wanted
        )

        let ladders = Self.ladders(from: ladder)
        let current = ladder.current.compactMapValues(Money.init(string:))

        try printToday(current, home: home, ladders: ladders)

        guard let amount = try resolveBase(current: current, home: home, ladders: ladders) else {
            return
        }
        print("")
        print("Working from \(amount) in \(home).")

        // The anchors need the base price, so they are read once it is known.
        let anchored = try await client.prices(
            for: product,
            baseTerritory: home,
            baseAmount: amount.description,
            territories: wanted
        )
        let read = Read(
            anchors: anchored.anchors.compactMapValues(Money.init(string:)),
            ladders: ladders,
            current: current
        )

        guard read.anchors.isEmpty == false else {
            print("")
            print("App Store Connect gave no equivalent prices for \(amount) in \(home).")
            print("That price is not one of the steps it sells at there. The steps near it:")
            printNearest(to: amount, in: ladders[home] ?? [])
            throw ExitCode.failure
        }

        if let name = curve {
            try printOne(name, amount: amount, home: home, read: read)
        } else {
            printEvery(amount: amount, home: home, read: read)
        }
    }

    /// The three things every step below needs, which always travel
    /// together: what the store would charge, what it can charge, and what it
    /// charges today.
    private struct Read {
        let anchors: [String: Money]
        let ladders: [String: [PricePoint]]
        let current: [String: Money]
    }

    // MARK: - What it costs now

    private func printToday(
        _ current: [String: Money],
        home: String,
        ladders: [String: [PricePoint]]
    ) throws {
        print("")
        guard current.isEmpty == false else {
            print("App Store Connect charges nothing for this yet, in any country.")
            print("\(ladders.count) countries have prices to choose from.")
            return
        }

        print("Charged today in \(current.count) countries.")
        if let athome = current[home] {
            print("  \(home)  \(athome)")
        }
        let others = current.keys.sorted().filter { $0 != home }.prefix(6)
        for id in others {
            guard let amount = current[id] else { continue }
            print("  \(id)  \(amount)")
        }
        if current.count > others.count + 1 {
            print("  ...and \(current.count - others.count - 1) more.")
        }
    }

    private func resolveBase(
        current: [String: Money],
        home: String,
        ladders: [String: [PricePoint]]
    ) throws -> Money? {
        if let written = base {
            guard let amount = Money(string: written) else {
                print("\(written) is not an amount. Write it as 14.99.")
                throw ExitCode.failure
            }
            return amount
        }

        guard let today = current[home] else {
            print("")
            print("Nothing is charged in \(home) yet, so there is no price to work from.")
            print("Pass --base to say what it should cost there. The steps near the middle "
                + "of what \(home) offers:")
            printNearest(to: nil, in: ladders[home] ?? [])
            return nil
        }
        return today
    }

    /// The steps around an amount, so a refusal shows what to write instead.
    private func printNearest(to amount: Money?, in ladder: [PricePoint]) {
        let ordered = ladder.map(\.customerPrice).sorted()
        guard ordered.isEmpty == false else {
            print("  (no prices read for that country)")
            return
        }

        guard let amount else {
            let middle = ordered.count / 2
            let window = ordered[max(0, middle - 4) ..< min(ordered.count, middle + 4)]
            print("  \(window.map(\.description).joined(separator: "  "))")
            return
        }

        let below = ordered.last { $0 < amount }
        let above = ordered.first { $0 > amount }
        print("  \(below?.description ?? "none")  and  \(above?.description ?? "none")")
    }

    // MARK: - What each curve would do

    /// A handful of countries that show the shape of a curve without printing
    /// all of them.
    private static let representative = [
        "USA", "GBR", "DEU", "JPN", "BRA", "IND", "IDN", "NGA", "TUR", "CHE"
    ]

    private func printEvery(
        amount: Money,
        home: String,
        read: Read
    ) {
        let shown = Self.representative.filter { read.ladders[$0] != nil }

        print("")
        print("What each curve would charge, in a few countries:")
        print("")
        print("  curve                  " + shown.map { $0.padding(toLength: 9, withPad: " ", startingAt: 0) }.joined())

        for curve in PriceCurve.all {
            let resolution = resolve(curve, amount: amount, home: home, read: read)
            let byTerritory = Dictionary(
                resolution.prices.map { ($0.territory, $0.customerPrice) },
                uniquingKeysWith: { first, _ in first }
            )
            let cells = shown.map { id in
                (byTerritory[id]?.description ?? "-")
                    .padding(toLength: 9, withPad: " ", startingAt: 0)
            }
            print("  " + curve.id.padding(toLength: 23, withPad: " ", startingAt: 0)
                + cells.joined())
        }

        if read.current.isEmpty == false {
            let cells = shown.map { id in
                (read.current[id]?.description ?? "-")
                    .padding(toLength: 9, withPad: " ", startingAt: 0)
            }
            print("  " + "charged today".padding(toLength: 23, withPad: " ", startingAt: 0)
                + cells.joined())
        }

        print("")
        for line in TextWrapping.lines(PriceResolver.roundingRule) {
            print(line)
        }
        print("")
        print("asckit price show \(productID) --curve <name> prints one of these country by country.")
        print("asckit price curves says what each one is for.")
    }

    private func printOne(
        _ name: String,
        amount: Money,
        home: String,
        read: Read
    ) throws {
        guard let curve = PriceCurve.named(name) else {
            print("\(name) is not a price curve ASCKit knows.")
            print("Use one of: \(PriceCurve.allIdentifiers.joined(separator: ", ")).")
            throw ExitCode.failure
        }

        let resolution = resolve(curve, amount: amount, home: home, read: read)

        print("")
        print("\(curve.displayName) (\(curve.id)), \(resolution.prices.count) countries.")
        print("")
        print("  country  today      would be   x      why")
        for price in resolution.prices {
            let today = (read.current[price.territory]?.description ?? "none")
                .padding(toLength: 10, withPad: " ", startingAt: 0)
            let now = price.customerPrice.description
                .padding(toLength: 10, withPad: " ", startingAt: 0)
            let multiplier = "\(price.multiplier)".padding(toLength: 6, withPad: " ", startingAt: 0)
            var why = describe(price.source)
            if price.roundedUpBy.isPositive { why += ", rounded up" }
            print("  \(price.territory)      \(today) \(now) \(multiplier) \(why)")
        }

        for problem in resolution.problems where problem.severity == .warning {
            print("")
            print(String(localized: problem.message))
        }

        print("")
        for line in TextWrapping.lines(PriceResolver.roundingRule) {
            print(line)
        }
    }

    private func describe(_ source: PriceResolver.Source) -> String {
        switch source {
        case .base: "the base price"
        case let .curve(band): band ?? "Apple's own price"
        case .overrideAmount, .overridePricePoint: "set by hand"
        }
    }

    private func resolve(
        _ curve: PriceCurve,
        amount: Money,
        home: String,
        read: Read
    ) -> PriceResolver.Resolution {
        PriceResolver.resolve(
            productID: productID,
            plan: Product.PricePlan(baseTerritory: home, baseAmount: amount, curve: curve.id),
            curve: curve,
            anchors: read.anchors,
            ladders: read.ladders,
            territories: Array(read.ladders.keys)
        )
    }

    private static func ladders(from read: RemotePrices) -> [String: [PricePoint]] {
        read.ladders.mapValues { points in
            points.compactMap { point in
                Money(string: point.customerPrice).map {
                    PricePoint(
                        id: point.id,
                        territory: point.territory,
                        customerPrice: $0,
                        proceeds: point.proceeds.flatMap(Money.init(string:)),
                        currency: nil
                    )
                }
            }
        }
    }
}
