import Foundation

/// Every price App Store Connect will sell one product at, kept on disk.
///
/// A ladder is 800 steps in each of 177 countries. Reading one costs four
/// batched requests, it is the slowest thing ASCKit does, and it barely changes
/// from one week to the next. So a read keeps it, and the next one opens a file.
///
/// It lives under `cache/price-points/` and is never in the repository. Every
/// number in it can be read again.
///
/// This is not `PricePointCache`, which sits beside it and holds a smaller,
/// identifier-free view for a caller with no network. Two files rather than
/// one, so a preview never has to decode megabytes of identifiers it does not
/// want, and so the smaller view still cannot name a price point.
public struct PriceLadderCache: Codable, Sendable {
    public static let formatVersion = 1

    public let version: Int

    /// The string the app asks the store for, which is also the file name.
    public let productID: String

    /// Apple's own id for the product.
    ///
    /// A price point id encodes the product it belongs to, so a ladder read for
    /// one product is not a wrong number on another: it is a refusal at best
    /// and somebody else's price at worst. A recreated purchase gets a new id,
    /// and this is what notices.
    public let remoteProductID: String

    /// Which endpoint the ladder came off. A subscription's points are not
    /// valid on a one-time purchase, so a `kind` somebody changed in the
    /// product file has to make this file unusable.
    public let isAutoRenewable: Bool

    /// `2026-08-30`, the day the numbers were read. A plain string, because it
    /// is a fact about the file rather than a moment in this program's life.
    public let readOn: String

    /// The base the anchors were read for. Apple answers about one price, so a
    /// file read for another one cannot answer this product's question.
    public let baseTerritory: String
    public let baseAmount: Money

    /// What App Store Connect would itself charge in each country for
    /// `baseAmount`. The numbers a curve multiplies.
    public let anchors: [String: Money]

    /// The ladder, one country at a time.
    ///
    /// A country ASCKit asked about and Apple sells nothing in is simply not
    /// here, which is why `readForTerritories` exists beside it.
    public let ladders: [String: Steps]

    /// The countries this file was read for.
    ///
    /// Not the same as the ones in `ladders`. Apple answers about the countries
    /// it sells the product in, so asking about 177 can come back with fewer,
    /// and a rule written against what came back would throw every file away.
    ///
    /// What matters is that the question was the same. A file read before
    /// ASCKit added a country cannot answer for it, and a country missing from
    /// a plan is a country left out of the write.
    public let readForTerritories: [String]

    /// One country's rungs, as two arrays of the same length rather than an
    /// array of objects.
    ///
    /// An object per rung repeats four keys a hundred and forty thousand times,
    /// which was most of the file before it was compressed and most of the time
    /// spent decoding it after.
    public struct Steps: Codable, Sendable, Hashable {
        public let ids: [String]
        public let prices: [Money]

        public init(ids: [String], prices: [Money]) {
            self.ids = ids
            self.prices = prices
        }
    }

    public init(
        version: Int = PriceLadderCache.formatVersion,
        productID: String,
        remoteProductID: String,
        isAutoRenewable: Bool,
        readOn: String,
        baseTerritory: String,
        baseAmount: Money,
        anchors: [String: Money],
        ladders: [String: Steps],
        readForTerritories: [String]
    ) {
        self.version = version
        self.productID = productID
        self.remoteProductID = remoteProductID
        self.isAutoRenewable = isAutoRenewable
        self.readOn = readOn
        self.baseTerritory = baseTerritory
        self.baseAmount = baseAmount
        self.anchors = anchors
        self.ladders = ladders
        self.readForTerritories = readForTerritories
    }

    // MARK: - Reading it back as a ladder

    /// One country's rungs, built exactly the way a read from App Store Connect
    /// builds them.
    ///
    /// The currency is nil, and that is not an oversight. A point read off
    /// Apple carries no currency either, so `ChangePlan.Row.currency` is always
    /// nil and always goes into the digest as nothing. A currency here would
    /// make a plan from this file differ from a plan from the network in every
    /// row, and refuse every push.
    ///
    /// Proceeds are nil for a plainer reason: nothing downstream reads them.
    public func points(for territory: String) -> [PricePoint] {
        guard let steps = ladders[territory] else { return [] }

        return zip(steps.ids, steps.prices).map { id, price in
            PricePoint(id: id, territory: territory, customerPrice: price, currency: nil)
        }
    }

    /// The whole ladder, in the shape a plan wants it.
    public var everyLadder: [String: [PricePoint]] {
        Dictionary(uniqueKeysWithValues: ladders.keys.map { ($0, points(for: $0)) })
    }

    // MARK: - Whether it still answers the question

    /// Whether this file still describes this product at this price.
    ///
    /// Strict on purpose. Every one of these, wrong, writes a price nobody
    /// chose.
    ///
    /// - Parameter territories: Every country ASCKit would ask App Store
    ///   Connect about now. It has to be the same list this file was read for,
    ///   in either direction. A country added since drops out of the plan, and
    ///   for a one-time purchase a country left out of the write goes back to
    ///   Apple's own equalized price. A country removed since would be written
    ///   when nothing asked for it.
    public func isUsable(
        for plan: Product.PricePlan,
        on remote: RemoteProductIdentity,
        covering territories: [String]
    ) -> Bool {
        version == Self.formatVersion
            && remoteProductID == remote.id
            && isAutoRenewable == remote.isAutoRenewable
            && baseTerritory == plan.baseTerritory
            && baseAmount == plan.baseAmount
            && anchors.isEmpty == false
            && ladders.isEmpty == false
            && Set(readForTerritories) == Set(territories)
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

    /// Where one product's prices came from, so a window can say so.
    public enum Origin: Sendable, Hashable {
        case network
        case cache(readOn: String)
    }
}

/// The two things about a product on App Store Connect that decide whether a
/// kept ladder belongs to it.
///
/// A small value rather than `RemoteProduct`, so `PriceLadderCache` states what
/// it needs and a test can hand it two fields.
public struct RemoteProductIdentity: Sendable, Hashable {
    public let id: String
    public let isAutoRenewable: Bool

    public init(id: String, isAutoRenewable: Bool) {
        self.id = id
        self.isAutoRenewable = isAutoRenewable
    }
}

// MARK: - Reading and writing it

/// The file itself: eight bytes saying what it is, then LZFSE.
public enum PriceLadderStore {
    static let folderName = PricePointStore.folderName
    static let fileExtension = "ladder"

    /// Eight bytes at the front, so a stray file or a half-written one is
    /// recognised rather than handed to a decompressor to guess at. The digit
    /// moves if the format ever does.
    static let magic = Data("ASCLADR1".utf8)

    public static func url(productID: String, in project: Project) -> URL {
        project.cacheURL
            .appending(path: folderName)
            .appending(path: "\(productID).\(fileExtension)")
    }

    /// Nil when nothing has read this product's ladder, when the file is not
    /// one of ours, or when it was cut short. Every one of those means the same
    /// thing to a caller: ask App Store Connect.
    public static func load(productID: String, in project: Project) -> PriceLadderCache? {
        guard
            let data = try? Data(contentsOf: url(productID: productID, in: project)),
            data.count > magic.count,
            data.prefix(magic.count) == magic,
            let json = try? (Data(data.dropFirst(magic.count)) as NSData)
            .decompressed(using: .lzfse) as Data
        else {
            return nil
        }
        return try? JSONDecoder().decode(PriceLadderCache.self, from: json)
    }

    /// Written whole or not at all. A torn JSON file is merely truncated, and a
    /// torn LZFSE file is nothing at all, so this one has to be atomic.
    public static func save(_ cache: PriceLadderCache, in project: Project) throws {
        // The cache folder needs the `.gitignore` that empties it. A project
        // made before that folder existed has neither, and this writes megabytes
        // per product. `makeCache` leaves an existing one alone.
        try ProjectScaffold.makeCache(in: project.rootURL)

        let url = url(productID: cache.productID, in: project)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        // Not pretty printed. A ladder is a hundred thousand rows, nobody reads
        // it, and this file is compressed anyway.
        let squeezed = try (ProjectJSON.encoder(pretty: false).encode(cache) as NSData).compressed(using: .lzfse) as Data
        try (magic + squeezed).write(to: url, options: .atomic)
    }

    /// Takes a kept ladder away. Nothing here needs it, and a caller that knows
    /// a product is gone does.
    public static func remove(productID: String, in project: Project) throws {
        let url = url(productID: productID, in: project)
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        try FileManager.default.removeItem(at: url)
    }
}
