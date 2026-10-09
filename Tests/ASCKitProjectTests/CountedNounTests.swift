import ASCKitProject
import Testing

struct CountedNounTests {
    @Test(arguments: [
        (0, "files"), (1, "file"), (2, "files"), (3, "files")
    ])
    func agreesTheNounWithTheCount(count: Int, noun: String) {
        #expect(countedNoun(count, "file") == "\(count) \(noun)")
    }

    @Test func agreesTheLastWordOfALongerNoun() {
        #expect(countedNoun(1, "app information file") == "1 app information file")
        #expect(countedNoun(3, "empty folder") == "3 empty folders")
    }
}
