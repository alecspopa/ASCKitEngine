import Foundation
import Testing
@testable import ASCKitProject

struct ProjectJSONTests {
    private struct Sample: Codable, Equatable {
        var name: String
        var count: Int
        var when: Date
    }

    @Test func prettyOutputHasSortedKeysAndKeepsSlashes() throws {
        let data = try ProjectJSON.encoder().encode(["z": "a/b", "a": "c"])
        #expect(String(bytes: data, encoding: .utf8) == "{\n  \"a\" : \"c\",\n  \"z\" : \"a/b\"\n}")
    }

    @Test func compactOutputHasNoWhitespace() throws {
        let data = try ProjectJSON.encoder(pretty: false).encode(["z": "1", "a": "2"])
        #expect(String(bytes: data, encoding: .utf8) == "{\"a\":\"2\",\"z\":\"1\"}")
    }

    @Test func writeRoundTripsDatesAsISO8601() throws {
        let url = FileManager.default.temporaryDirectory.appending(path: "json-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: url) }
        let value = Sample(name: "x", count: 1, when: Date(timeIntervalSince1970: 1_700_000_000))

        try ProjectJSON.write(value, to: url, datesAsISO8601: true, atomic: true)

        let text = try String(contentsOf: url, encoding: .utf8)
        #expect(text.contains("2023-11-14T22:13:20Z"))
        let back = try ProjectJSON.decoder(datesAsISO8601: true).decode(Sample.self, from: Data(contentsOf: url))
        #expect(back == value)
    }

    @Test func naturalSortReadsNumbersByValue() {
        #expect("2.png".isNaturallyBefore("10.png"))
        #expect("10.png".isNaturallyBefore("2.png") == false)
        let urls = ["b/10", "a/2"].map { URL(fileURLWithPath: $0) }
        #expect(urls.sortedNaturally().map(\.lastPathComponent) == ["2", "10"])
        #expect(urls.sortedNaturally(by: \.path).map(\.path) == ["a/2", "b/10"].map { URL(fileURLWithPath: $0).path })
    }
}
