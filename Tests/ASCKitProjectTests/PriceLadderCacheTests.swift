import Foundation
import Testing
@testable import ASCKitProject

/// The ladder a project keeps on disk, so opening a price page does not cost a
/// hundred requests.
///
/// Two things are worth more than the rest here. A point read back out has to
/// match a point read off App Store Connect field for field, or a plan built
/// from this file differs from a plan built from the network and every push is
/// refused. And every reason a file stops describing its product has to make it
/// unusable, because each of them writes a price nobody chose.
struct PriceLadderCacheTests {
    let plan = Product.PricePlan(baseTerritory: "USA", baseAmount: Money(string: "4.99")!, curve: "apple-equalized")
    let identity = RemoteProductIdentity(id: "sub1", isAutoRenewable: true)

    func cache(
        remoteProductID: String = "sub1",
        isAutoRenewable: Bool = true,
        baseTerritory: String = "USA",
        baseAmount: String = "4.99",
        anchors: [String: String] = ["USA": "4.99", "DEU": "5.99"],
        territories: [String] = ["USA", "DEU"],
        readForTerritories: [String]? = nil,
        version: Int = PriceLadderCache.formatVersion
    ) -> PriceLadderCache {
        PriceLadderCache(
            version: version,
            productID: "com.example.pro",
            remoteProductID: remoteProductID,
            isAutoRenewable: isAutoRenewable,
            readOn: "2026-08-30",
            baseTerritory: baseTerritory,
            baseAmount: Money(string: baseAmount)!,
            anchors: anchors.compactMapValues(Money.init(string:)),
            ladders: Dictionary(uniqueKeysWithValues: territories.map { territory in
                (territory, PriceLadderCache.Steps(
                    ids: ["\(territory)-399", "\(territory)-499"],
                    prices: [Money(string: "3.99")!, Money(string: "4.99")!]
                ))
            }),
            readForTerritories: readForTerritories ?? territories
        )
    }

    // MARK: - Reading it back as a ladder

    @Test func aRungKeepsAppleSIdentifierExactly() {
        let points = cache().points(for: "USA")

        #expect(points.map(\.id) == ["USA-399", "USA-499"])
        #expect(points.map(\.customerPrice.description) == ["3.99", "4.99"])
        #expect(points.allSatisfy { $0.territory == "USA" })
    }

    /// A point read off App Store Connect carries no currency, so one read off
    /// disk must not carry one either. `ChangePlan.Row.currency` goes into the
    /// digest, and a currency on one side only refuses every push.
    @Test func aRungCarriesNoCurrency() {
        #expect(cache().points(for: "USA").allSatisfy { $0.currency == nil })
    }

    @Test func aCountryTheFileDoesNotHoldHasNoRungs() {
        #expect(cache().points(for: "JPN").isEmpty)
    }

    @Test func everyLadderHoldsOneEntryPerCountry() {
        #expect(Set(cache().everyLadder.keys) == ["USA", "DEU"])
    }

    // MARK: - Whether it still answers the question

    @Test func aFileReadForThisProductAtThisPriceIsUsable() {
        #expect(cache().isUsable(for: plan, on: identity, covering: ["USA", "DEU"]))
    }

    @Test func aFileReadForAnotherBaseAmountIsNotUsable() {
        let other = cache(baseAmount: "3.99")
        #expect(other.isUsable(for: plan, on: identity, covering: ["USA", "DEU"]) == false)
    }

    @Test func aFileReadForAnotherBaseTerritoryIsNotUsable() {
        let other = cache(baseTerritory: "DEU")
        #expect(other.isUsable(for: plan, on: identity, covering: ["USA", "DEU"]) == false)
    }

    /// A price point id encodes the product it belongs to. A purchase recreated
    /// on App Store Connect gets a new id, and its old ladder is somebody
    /// else's prices.
    @Test func aFileReadForAnotherProductIsNotUsable() {
        let other = cache(remoteProductID: "sub2")
        #expect(other.isUsable(for: plan, on: identity, covering: ["USA", "DEU"]) == false)
    }

    /// A subscription's points are not valid on a one-time purchase, so a kind
    /// somebody changed in the product file throws the ladder away.
    @Test func aFileReadOffTheOtherEndpointIsNotUsable() {
        let other = cache(isAutoRenewable: false)
        #expect(other.isUsable(for: plan, on: identity, covering: ["USA", "DEU"]) == false)
    }

    /// Apple answers with no equivalent prices when the base amount is not a
    /// real step. That answer must not be frozen onto disk.
    @Test func aFileWithNoAnchorsIsNotUsable() {
        let other = cache(anchors: [:])
        #expect(other.isUsable(for: plan, on: identity, covering: ["USA", "DEU"]) == false)
    }

    /// The one that surprises. A plan resolves over the countries the ladder
    /// holds, so a country ASCKit learned about since drops out of the plan,
    /// and a country left out of a one-time purchase's write goes back to
    /// Apple's own price.
    @Test func aFileReadBeforeACountryWasAddedIsNotUsable() {
        let other = cache(territories: ["USA"], readForTerritories: ["USA"])
        #expect(other.isUsable(for: plan, on: identity, covering: ["USA", "DEU"]) == false)
    }

    /// The other direction. A file read for a country ASCKit no longer asks
    /// about would put that country back into a write.
    @Test func aFileReadForACountryThatIsGoneIsNotUsable() {
        #expect(cache().isUsable(for: plan, on: identity, covering: ["USA"]) == false)
    }

    /// Apple answers about the countries it sells the product in, so asking
    /// about two and hearing about one is an answer rather than a gap. The
    /// question is what has to match, not the reply.
    @Test func aCountryAppleSellsNothingInDoesNotSpoilTheFile() {
        let other = cache(territories: ["USA"], readForTerritories: ["USA", "DEU"])
        #expect(other.isUsable(for: plan, on: identity, covering: ["USA", "DEU"]))
    }

    @Test func aFileInAnOlderFormatIsNotUsable() {
        let other = cache(version: PriceLadderCache.formatVersion - 1)
        #expect(other.isUsable(for: plan, on: identity, covering: ["USA", "DEU"]) == false)
    }

    // MARK: - The file on disk

    func fixture() throws -> FixtureProject {
        let fixture = try FixtureProject()
        _ = try fixture.writeConfig(ProjectConfig(bundleID: "com.example.MyApp", keyID: "ABC123"))
        return fixture
    }

    @Test func aLadderComesBackOffDiskExactlyAsItWentOn() throws {
        let fixture = try fixture()
        defer { fixture.remove() }
        let project = try fixture.load()

        try PriceLadderStore.save(cache(), in: project)
        let read = try #require(PriceLadderStore.load(productID: "com.example.pro", in: project))

        #expect(read.remoteProductID == "sub1")
        #expect(read.baseAmount == Money(string: "4.99"))
        #expect(read.readOn == "2026-08-30")
        #expect(read.points(for: "DEU") == cache().points(for: "DEU"))
    }

    @Test func nothingComesBackWhenNothingHasBeenRead() throws {
        let fixture = try fixture()
        defer { fixture.remove() }
        #expect(try PriceLadderStore.load(productID: "com.example.pro", in: fixture.load()) == nil)
    }

    /// A ladder is megabytes. Compressed it is not JSON, so anything that hands
    /// it to a JSON reader has to fail rather than half succeed.
    @Test func theFileIsNotReadableJSON() throws {
        let fixture = try fixture()
        defer { fixture.remove() }
        let project = try fixture.load()

        try PriceLadderStore.save(cache(), in: project)
        let data = try Data(
            contentsOf: PriceLadderStore.url(productID: "com.example.pro", in: project)
        )

        #expect(data.prefix(8) == PriceLadderStore.magic)
        #expect((try? JSONSerialization.jsonObject(with: data)) == nil)
    }

    @Test func aFileThatIsNotOneOfOursReadsAsNothing() throws {
        let fixture = try fixture()
        defer { fixture.remove() }
        let project = try fixture.load()
        let url = PriceLadderStore.url(productID: "com.example.pro", in: project)

        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        try Data("not a ladder".utf8).write(to: url)

        #expect(PriceLadderStore.load(productID: "com.example.pro", in: project) == nil)
    }

    @Test func aFileCutShortReadsAsNothing() throws {
        let fixture = try fixture()
        defer { fixture.remove() }
        let project = try fixture.load()
        let url = PriceLadderStore.url(productID: "com.example.pro", in: project)

        try PriceLadderStore.save(cache(), in: project)
        let whole = try Data(contentsOf: url)
        try whole.prefix(whole.count / 2).write(to: url)

        #expect(PriceLadderStore.load(productID: "com.example.pro", in: project) == nil)
    }

    /// The cache folder needs the rule that empties it. A project made before
    /// that folder existed has neither, and this writes megabytes per product.
    @Test func savingMakesTheGitignoreThatEmptiesTheCacheFolder() throws {
        let fixture = try fixture()
        defer { fixture.remove() }
        let project = try fixture.load()

        try PriceLadderStore.save(cache(), in: project)

        let ignore = project.cacheURL.appending(path: ".gitignore")
        #expect(FileManager.default.fileExists(atPath: ignore.path))
    }

    @Test func aLadderCanBeTakenAway() throws {
        let fixture = try fixture()
        defer { fixture.remove() }
        let project = try fixture.load()

        try PriceLadderStore.save(cache(), in: project)
        try PriceLadderStore.remove(productID: "com.example.pro", in: project)

        #expect(PriceLadderStore.load(productID: "com.example.pro", in: project) == nil)
    }

    @Test func takingAwayALadderThatIsNotThereIsNotAFailure() throws {
        let fixture = try fixture()
        defer { fixture.remove() }
        #expect(throws: Never.self) {
            try PriceLadderStore.remove(productID: "com.example.pro", in: fixture.load())
        }
    }
}
