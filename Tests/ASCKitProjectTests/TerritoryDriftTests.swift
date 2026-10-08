import Foundation
import Testing
@testable import ASCKitProject

struct TerritoryDriftTests {
    private let table = [
        Territory(id: "DEU", regionCode: "DE", currency: "EUR"),
        Territory(id: "SRB", regionCode: "RS", currency: "EUR"),
        Territory(id: "USA", regionCode: "US", currency: "USD")
    ]

    @Test func agreesWithATableThatMatches() {
        let drift = TerritoryDrift.compare(
            remote: ["DEU": "EUR", "SRB": "EUR", "USA": "USD"],
            table: table
        )
        #expect(drift.agrees)
    }

    @Test func namesATerritoryMissingOnEachSide() {
        let drift = TerritoryDrift.compare(
            remote: ["DEU": "EUR", "SRB": "EUR", "XKS": "EUR"],
            table: table
        )
        #expect(drift.missingHere == ["XKS"])
        #expect(drift.missingThere == ["USA"])
        #expect(drift.currencies.isEmpty)
    }

    @Test func namesACurrencyThatChanged() {
        let drift = TerritoryDrift.compare(
            remote: ["DEU": "EUR", "SRB": "RSD", "USA": "USD"],
            table: table
        )
        #expect(drift.currencies == [
            TerritoryDrift.CurrencyChange(territory: "SRB", table: "EUR", appStoreConnect: "RSD")
        ])
    }
}
