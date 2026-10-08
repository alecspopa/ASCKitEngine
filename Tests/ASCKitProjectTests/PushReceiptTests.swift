import Foundation
import Testing
@testable import ASCKitProject

/// A push says what happened once, on a terminal nobody keeps. The receipt is
/// the record.
final class PushReceiptTests {
    let fixture: FixtureProject
    let moment = Date(timeIntervalSince1970: 1_755_700_000)

    init() throws {
        fixture = try FixtureProject()
        try fixture.writeConfig(ProjectConfig(bundleID: "com.example.Demo", keyID: "ABC123"))
    }

    deinit {
        fixture.remove()
    }

    func receipt(
        at date: Date? = nil,
        written: [String] = ["en-US"],
        refused: [PushReceipt.RefusedField] = [],
        failed: [PushReceipt.FailedLocale] = []
    ) -> PushReceipt {
        PushReceipt(
            pushedAt: date ?? moment,
            kind: .text,
            version: "1.0",
            appVersionState: "PREPARE_FOR_SUBMISSION",
            written: written,
            refused: refused,
            failed: failed
        )
    }

    // MARK: - Naming

    /// Sorted by name is sorted by time, so the folder reads in order.
    @Test func namesReceiptsSoTheySortByTime() {
        let earlier = PushHistory.fileName(for: receipt(at: moment))
        let later = PushHistory.fileName(for: receipt(at: moment.addingTimeInterval(3600)))

        #expect(earlier < later)
        #expect(earlier.hasSuffix("-1.0-text.json"))
    }

    /// A colon is legal in a file name on this file system and a nuisance
    /// everywhere else.
    @Test func keepsColonsOutOfTheFileName() {
        #expect(PushHistory.fileName(for: receipt()).contains(":") == false)
    }

    // MARK: - Writing and reading

    @Test func writesAReceiptAndReadsItBack() throws {
        let project = try fixture.load()
        try PushHistory.write(receipt(), to: project)

        let read = PushHistory.read(from: project)
        #expect(read.count == 1)
        #expect(read.first?.written == ["en-US"])
        #expect(read.first?.version == "1.0")
    }

    /// The whole reason for the receipt: what App Store Connect refused, and
    /// the words it used.
    @Test func keepsTheReasonAppStoreConnectGave() throws {
        let project = try fixture.load()
        try PushHistory.write(
            receipt(refused: [.init(
                locale: "en-US",
                field: "whatsNew",
                reason: "Attribute 'whatsNew' cannot be edited at this time."
            )]),
            to: project
        )

        let refusal = try #require(PushHistory.read(from: project).first?.refused.first)
        #expect(refusal.field == "whatsNew")
        #expect(refusal.reason.contains("cannot be edited at this time"))
    }

    @Test func readsTheNewestFirst() throws {
        let project = try fixture.load()
        try PushHistory.write(receipt(at: moment, written: ["older"]), to: project)
        try PushHistory.write(
            receipt(at: moment.addingTimeInterval(3600), written: ["newer"]),
            to: project
        )

        #expect(PushHistory.read(from: project).map(\.written) == [["newer"], ["older"]])
    }

    @Test func readsNothingFromAProjectThatHasPushedNothing() throws {
        #expect(try PushHistory.read(from: fixture.load()).isEmpty)
    }

    /// One unreadable file must not hide every other receipt.
    @Test func skipsAFileItCannotRead() throws {
        let project = try fixture.load()
        try PushHistory.write(receipt(), to: project)
        try Data("not json".utf8).write(to: project.historyURL.appending(path: "broken.json"))

        #expect(PushHistory.read(from: project).count == 1)
    }

    // MARK: - Built from a push

    @Test func recordsWhatTheTextPushReported() {
        var result = TextPusher.Result()
        result.written = ["en-US"]
        result.refused = [.init(
            locale: "en-US",
            field: .whatsNew,
            reason: "Attribute 'whatsNew' cannot be edited at this time."
        )]

        let receipt = PushReceipt.forText(
            result,
            version: "1.0",
            appVersionState: "PREPARE_FOR_SUBMISSION",
            at: moment
        )

        #expect(receipt.kind == .text)
        #expect(receipt.written == ["en-US"])
        #expect(receipt.refused.map(\.field) == ["whatsNew"])
        #expect(receipt.isCompleteSuccess == false, "a refused field is not a clean push")
    }

    @Test func callsAPushWithNothingRefusedASuccess() {
        var result = TextPusher.Result()
        result.written = ["en-US"]

        let receipt = PushReceipt.forText(result, version: "1.0", appVersionState: nil, at: moment)
        #expect(receipt.isCompleteSuccess)
    }

    @Test func recordsWhichSetFailedForImages() {
        var result = ScreenshotPusher.Result()
        result.uploaded = ["en-US|iphone-6.9"]
        result.failed = [.init(
            locale: "de-DE",
            deviceClassID: "ipad-13",
            message: "Wrong size."
        )]

        let receipt = PushReceipt.forImages(result, version: "1.0", appVersionState: nil, at: moment)

        #expect(receipt.kind == .images)
        #expect(receipt.failed.first?.locale == "de-DE ipad-13")
    }

    @Test func recordsTheAssetAndPlacementIdsOfEachSlot() {
        var result = ScreenshotPusher.Result()
        result.uploaded = ["en-US|iphone-6.9"]
        result.slots = [.init(
            slot: "en-US|iphone-6.9", assetIDs: ["a1", "a2"], placementIDs: ["p1", "p2"],
            removedPlacementIDs: ["p0"], uploadedAssetIDs: ["a2"]
        )]

        let receipt = PushReceipt.forImages(result, version: "1.0", appVersionState: nil, at: moment)
        #expect(receipt.library == [.init(
            slot: "en-US|iphone-6.9", assetIDs: ["a1", "a2"], placementIDs: ["p1", "p2"],
            removedPlacementIDs: ["p0"], uploadedAssetIDs: ["a2"]
        )])
        #expect(PushReceipt.forExperimentImages(result, at: moment).library?.first?.placementIDs == ["p1", "p2"])
    }

    /// Receipts written before the asset library have no ids, and still read.
    @Test func readsAReceiptWrittenBeforeTheLibrary() throws {
        let old = """
        {"pushedAt":"2026-09-01T10:00:00Z","kind":"images","version":"1.0",
         "written":["en-US|iphone-6.9"],"refused":[],"failed":[]}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let receipt = try decoder.decode(PushReceipt.self, from: Data(old.utf8))
        #expect(receipt.library == nil)
        #expect(receipt.written == ["en-US|iphone-6.9"])
    }

    @Test func writesTheIdsAndReadsThemBack() throws {
        var result = ScreenshotPusher.Result()
        result.slots = [.init(slot: "en-US|header", assetIDs: ["h1"], placementIDs: ["ph"],
                              removedPlacementIDs: [], uploadedAssetIDs: ["h1"])]
        let project = try fixture.load()

        try PushHistory.write(PushReceipt.forImages(result, version: "1.0", appVersionState: nil, at: moment),
                              to: project)

        #expect(PushHistory.read(from: project).first?.library?.first?.assetIDs == ["h1"])
    }
}
