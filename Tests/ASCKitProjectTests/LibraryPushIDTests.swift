import ASCKitAPI
import ASCKitTestSupport
import Foundation
import Testing
@testable import ASCKitProject

/// The ids a push reports for each slot it writes, which go into the receipt.
extension LibraryPusherTests {
    @Test func namesTheAssetsAndPlacementsOfASlotItFilled() async throws {
        defer { files.remove() }
        let one = try files.file("01.png")
        let transport = StubTransport([
            LibraryReply.reserved("new1"), .ok(""), LibraryReply.committed,
            LibraryReply.states([("new1", "PREPARE_FOR_SUBMISSION")]),
            LibraryReply.deleted,
            LibraryReply.placement("p-new")
        ])

        let pushed = try await push([target(local: [one], current: [Placed.placement("p-old", asset: "unknown")])],
                                    transport: transport)

        #expect(pushed.result.slots == [ScreenshotPusher.SlotWritten(
            slot: "en-US|iphone-6.9", assetIDs: ["new1"], placementIDs: ["p-new"],
            removedPlacementIDs: ["p-old"], uploadedAssetIDs: ["new1"]
        )])
    }

    @Test func namesNoUploadForAnAssetTheLibraryHeld() async throws {
        defer { files.remove() }
        let one = try files.file("01.png")
        let record = try LibraryFiles.record([(one, "a1")])
        let transport = StubTransport([LibraryReply.placement("p-new")])

        let pushed = try await push([target(local: [one], record: record)], transport: transport, record: record)

        #expect(pushed.result.slots.first?.assetIDs == ["a1"])
        #expect(pushed.result.slots.first?.uploadedAssetIDs == [])
        #expect(pushed.result.slots.first?.placementIDs == ["p-new"])
    }

    /// A reorder keeps every placement, so the ids are the same ones in the
    /// new order.
    @Test func namesTheKeptPlacementsInTheirNewOrder() async throws {
        defer { files.remove() }
        let one = try files.file("01.png"), two = try files.file("02.png")
        let record = try LibraryFiles.record([(one, "a1"), (two, "a2")])
        let transport = StubTransport([LibraryReply.ordered])

        let pushed = try await push(
            [target(local: [one, two], current: [Placed.placement("p2", asset: "a2"), Placed.placement("p1", asset: "a1")],
                    record: record)],
            transport: transport,
            record: record
        )

        #expect(pushed.result.slots.first?.placementIDs == ["p1", "p2"])
        #expect(pushed.result.slots.first?.removedPlacementIDs == [])
    }

    @Test func namesNoIdsForASlotThatFailed() async throws {
        defer { files.remove() }
        let one = try files.file("01.png")
        let record = try LibraryFiles.record([(one, "a1")])
        let transport = StubTransport([LibraryReply.refusal("STATE_ERROR.INVALID_STATE")])

        let pushed = try await push([target(local: [one], record: record)], transport: transport, record: record)

        #expect(pushed.result.failed.count == 1)
        #expect(pushed.result.slots.isEmpty)
    }
}
