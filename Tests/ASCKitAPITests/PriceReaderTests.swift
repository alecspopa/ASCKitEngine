import ASCKitTestSupport
import Foundation
import Testing
@testable import ASCKitAPI

/// What a product costs today. A wrong "no price" here makes a price rise
/// look like no change, so only a missing schedule may read as empty.
struct PriceReaderTests {
    let purchase = RemoteProduct(id: "p1", productID: "com.example.coins", kind: "consumable")

    @Test func aPurchaseWithNoScheduleHasNoPrices() async throws {
        let transport = StubTransport(routes: [
            ("/iapPriceSchedule", .failure(404))
        ])
        let client = try ASCClient.stubbed(transport: transport)

        let prices = try await client.currentPrices(for: purchase)

        #expect(prices.current.isEmpty)
    }

    @Test func aFailedScheduleReadStopsTheRead() async throws {
        let transport = StubTransport(routes: [
            ("/iapPriceSchedule", .failure(500))
        ])
        let client = try ASCClient.stubbed(transport: transport)

        await #expect(throws: ASCError.self) {
            try await client.currentPrices(for: purchase)
        }
    }
}
