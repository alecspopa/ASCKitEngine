import Foundation

/// What App Store Connect answered about one product's prices, kept on disk.
///
/// A caller with no network and no key cannot ask Apple for a price ladder.
/// So a caller that wants to say what a curve would charge has to read what an
/// earlier command already asked for. This is that file.
///
/// It lives under `cache/price-points/` and is never in the repository. Every
/// number in it can be read again, and a ladder goes out of date when Apple
/// moves one, so keeping it would only let two clones disagree.
public struct PricePointCache: Codable, Sendable {
    public let productID: String

    /// `2026-08-30`, the day the numbers were read. A plain string, because it
    /// is a fact about the file rather than a moment in this program's life.
    public let readOn: String

    /// The base the anchors were read for. An anchor is Apple's answer to one
    /// price, so a preview of a different base price works from a scaled number
    /// rather than from Apple's own.
    public let baseTerritory: String
    public let baseAmount: Money

    /// What App Store Connect would charge in each country for `baseAmount`.
    public let anchors: [String: Money]

    /// What each country pays today.
    public let current: [String: Money]

    /// What one instalment costs today, where the product is sold that way.
    public let currentMonthly: [String: Money]

    /// Every price this product can be sold at, keyed by country.
    ///
    /// Prices, not price points. A point carries Apple's opaque identifier,
    /// which is most of its bytes: one product's whole ladder came to 17 MB
    /// with the identifiers and under one without them.
    ///
    /// Leaving them out is the safer shape as well as the smaller one. This
    /// file works a price out and never writes one, and an identifier is the
    /// thing a write needs. Nothing reading this can send a price by accident.
    public let ladders: [String: [Money]]

    /// The price points a product file names by hand in an override.
    ///
    /// The one case a preview needs an identifier for, and there are a handful
    /// rather than a hundred thousand. Without them an override by price point
    /// would preview as "no such point", which reads as a broken file when the
    /// file is fine.
    public let namedPoints: [PricePoint]

    public init(
        productID: String,
        readOn: String,
        baseTerritory: String,
        baseAmount: Money,
        anchors: [String: Money],
        current: [String: Money] = [:],
        currentMonthly: [String: Money] = [:],
        ladders: [String: [Money]],
        namedPoints: [PricePoint] = []
    ) {
        self.productID = productID
        self.readOn = readOn
        self.baseTerritory = baseTerritory
        self.baseAmount = baseAmount
        self.anchors = anchors
        self.current = current
        self.currentMonthly = currentMonthly
        self.ladders = ladders
        self.namedPoints = namedPoints
    }

    /// Every price in one country, as the resolver wants them.
    ///
    /// The identifier on each is `\(Self.notReadIdentifier)`, because this
    /// file does not hold the real one. A price point somebody named by hand
    /// keeps its own, so an override still resolves.
    public func ladder(for territory: String) -> [PricePoint] {
        let named = namedPoints.filter { $0.territory == territory }
        let prices = (ladders[territory] ?? []).map { price in
            PricePoint(id: Self.notReadIdentifier, territory: territory, customerPrice: price)
        }
        return named + prices
    }

    /// What stands in for a price point identifier here. Not a real one, and
    /// shaped so that sending it to App Store Connect could only ever fail.
    public static let notReadIdentifier = "not-read"

    /// Whether a product file names a price point this cache cannot resolve.
    public func cannotResolve(_ plan: Product.PricePlan) -> [String] {
        let known = Set(namedPoints.map(\.id))
        return plan.overrides
            .compactMap { territory, override in
                guard let point = override.pricePoint, known.contains(point) == false else {
                    return nil
                }
                return territory
            }
            .sorted()
    }

    /// Codable by hand, so a file written before `namedPoints` existed still
    /// reads. A cache can be thrown away, but throwing one away costs a
    /// hundred requests to Apple.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        productID = try container.decode(String.self, forKey: .productID)
        readOn = try container.decode(String.self, forKey: .readOn)
        baseTerritory = try container.decode(String.self, forKey: .baseTerritory)
        baseAmount = try container.decode(Money.self, forKey: .baseAmount)
        anchors = try container.decode([String: Money].self, forKey: .anchors)
        current = try container.decodeIfPresent([String: Money].self, forKey: .current) ?? [:]
        currentMonthly = try container.decodeIfPresent(
            [String: Money].self, forKey: .currentMonthly
        ) ?? [:]
        ladders = try container.decode([String: [Money]].self, forKey: .ladders)
        namedPoints = try container.decodeIfPresent(
            [PricePoint].self, forKey: .namedPoints
        ) ?? []
    }

    /// The anchors to price a base amount from.
    ///
    /// Apple answers with the equivalent of one price. Ask about another and
    /// the honest answer is a scaled one, because the ladder is close to linear
    /// in the middle and the rounding up to a real point absorbs the rest.
    /// Close is not exact, so the preview says which of the two it used.
    public func anchors(for amount: Money) -> [String: Money] {
        guard amount != baseAmount, baseAmount.isPositive else { return anchors }
        let ratio = (amount.amount as NSDecimalNumber).doubleValue
            / (baseAmount.amount as NSDecimalNumber).doubleValue
        return anchors.mapValues { $0.scaled(by: ratio) }
    }

    /// Whether a base amount is the one Apple answered about.
    public func holdsAnchors(for amount: Money) -> Bool {
        amount == baseAmount
    }

    /// How many days old the numbers are, or nil when `readOn` is not a date.
    public func daysOld(on day: Date = .now) -> Int? {
        guard let read = Self.formatter.date(from: readOn) else { return nil }
        return Calendar(identifier: .gregorian).dateComponents([.day], from: read, to: day).day
    }

    public static func today(_ day: Date = .now) -> String {
        formatter.string(from: day)
    }

    /// A plain day, in no time zone anybody has to think about. POSIX so a
    /// person whose calendar is not Gregorian still gets 2026-08-30.
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}

// MARK: - Reading and writing it

public enum PricePointStore {
    static let folderName = "price-points"

    public static func url(productID: String, in project: Project) -> URL {
        project.cacheURL
            .appending(path: folderName)
            .appending(path: "\(productID).json")
    }

    /// Nil when nothing has read this product's prices yet, which is every
    /// product until somebody runs a command that needs them.
    public static func load(productID: String, in project: Project) -> PricePointCache? {
        let url = url(productID: productID, in: project)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(PricePointCache.self, from: data)
    }

    public static func save(_ cache: PricePointCache, in project: Project) throws {
        let url = url(productID: cache.productID, in: project)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        // Not pretty printed. A ladder is tens of thousands of rows, nobody
        // reads it, and the indentation would be most of the file.
        try ProjectJSON.write(cache, to: url, pretty: false)
    }
}
