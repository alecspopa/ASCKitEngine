import ASCKitAPI
import Foundation
import Testing
@testable import ASCKitProject

final class RetentionMessageStoreTests {
    var fixtures: [FixtureProject] = []

    deinit {
        fixtures.forEach { $0.remove() }
    }

    func project(locales: [String] = ["en-US"]) throws -> Project {
        let fixture = try FixtureProject()
        fixtures.append(fixture)
        _ = try fixture.writeConfig(ProjectConfig(bundleID: "com.example.MyApp", keyID: "ABC123", locales: locales))
        return try fixture.load()
    }

    func write(_ json: String, name: String, in project: Project) throws {
        let url = project.retentionMessageURL(name: name)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(json.utf8).write(to: url)
    }

    // MARK: - Reading and writing

    @Test func readsTheNameFromTheFileName() throws {
        let project = try project()
        try write(#"{"localizations":{"en-US":{"header":"Stay","body":"More soon"}}}"#, name: "Cancel", in: project)

        let catalog = ProductStore.load(in: project)
        let message = try #require(catalog.retentionMessages["Cancel"])
        #expect(message.referenceName == "Cancel")
        #expect(message.localizations["en-US"]?.header == "Stay")
        #expect(message.status == .draft)
    }

    @Test func roundTripsThroughTheWriter() throws {
        let project = try project()
        let message = RetentionMessage(
            referenceName: "Cancel", localizations: ["en-US": .init(header: "Stay", body: "More soon")]
        )
        try ContentWriter.writeRetentionMessage(message, in: project)
        #expect(ProductStore.load(in: project).retentionMessages["Cancel"] == message)
    }

    @Test func refusesANameWithASlash() throws {
        let project = try project()
        #expect(throws: ContentWriteError.self) {
            try ContentWriter.writeRetentionMessage(RetentionMessage(referenceName: "a/b"), in: project)
        }
    }

    @Test func reportsAFileThatDoesNotRead() throws {
        let project = try project()
        try write("{", name: "Broken", in: project)
        let catalog = ProductStore.load(in: project)
        #expect(catalog.unreadableRetentionMessages["Broken"] != nil)
        #expect(Validator(config: project.config).validate(catalog).contains { $0.kind == .retentionFileUnreadable })
    }

    // MARK: - Checks

    func problems(_ json: String, locales: [String] = ["en-US"]) throws -> [Problem] {
        let project = try project(locales: locales)
        try write(json, name: "Cancel", in: project)
        return Validator(config: project.config).validate(ProductStore.load(in: project))
    }

    @Test func acceptsAHeaderAndABody() throws {
        let found = try problems(#"{"localizations":{"en-US":{"header":"Stay","body":"More soon"}}}"#)
        #expect(found.filter { $0.retentionMessage != nil }.isEmpty)
    }

    @Test func refusesAHeaderOverSixtySixCharacters() throws {
        let header = String(repeating: "a", count: 67)
        let found = try problems(#"{"localizations":{"en-US":{"header":"\#(header)","body":"b"}}}"#)
        let problem = try #require(found.first { $0.kind == .retentionTextOverLimit })
        #expect(problem.severity == .error)
        #expect(problem.retentionField == .header)
    }

    @Test func refusesABodyOverOneHundredFortyFourCharacters() throws {
        let body = String(repeating: "b", count: 145)
        let found = try problems(#"{"localizations":{"en-US":{"header":"a","body":"\#(body)"}}}"#)
        #expect(found.contains { $0.kind == .retentionTextOverLimit && $0.retentionField == .body })
    }

    @Test func warnsAboutALanguageWithNoWords() throws {
        let found = try problems(
            #"{"localizations":{"en-US":{"header":"a","body":"b"}}}"#, locales: ["en-US", "de-DE"]
        )
        let missing = found.filter { $0.kind == .retentionTextNotTranslated }
        #expect(missing.map(\.locale) == ["de-DE", "de-DE"])
        #expect(missing.allSatisfy { $0.severity == .warning })
    }

    @Test func refusesAnEmptyHeader() throws {
        let found = try problems(#"{"localizations":{"en-US":{"header":"","body":"b"}}}"#)
        #expect(found.contains { $0.kind == .retentionTextEmpty && $0.severity == .error })
    }

    @Test func headerAndBodyWarningsAreTwoProblems() throws {
        let found = try problems(#"{"localizations":{"en-US":{"header":" a","body":" b"}}}"#)
        let edges = found.filter { $0.kind == .retentionTextHasEdgeSpace }
        #expect(Set(edges.map(\.id)).count == 2)
    }

    @Test func refusesTwoImages() throws {
        let project = try project()
        try write(#"{"localizations":{"en-US":{"header":"a","body":"b"}}}"#, name: "Cancel", in: project)
        for ext in ["png", "jpg"] {
            try Data().write(to: project.retentionMessagesURL.appending(path: "Cancel.\(ext)"))
        }
        let found = Validator(config: project.config).validate(ProductStore.load(in: project))
        #expect(found.contains { $0.kind == .retentionTwoImages })
    }

    @Test func refusesAFileThatIsNotAnImage() throws {
        let project = try project()
        try write(#"{"localizations":{"en-US":{"header":"a","body":"b"}}}"#, name: "Cancel", in: project)
        try Data("not an image".utf8).write(to: project.retentionMessagesURL.appending(path: "Cancel.png"))
        let found = Validator(config: project.config).validate(ProductStore.load(in: project))
        #expect(found.contains { $0.kind == .retentionImageUnreadable })
    }

    @Test func setsTheImageInPlaceOfTheOneThere() throws {
        let project = try project()
        try write(#"{"localizations":{}}"#, name: "Cancel", in: project)
        try Data("old".utf8).write(to: project.retentionMessagesURL.appending(path: "Cancel.jpg"))
        let source = FileManager.default.temporaryDirectory.appending(path: "\(UUID().uuidString).png")
        try Data("new".utf8).write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }

        try ContentWriter.setRetentionImage(from: source, message: "Cancel", in: project)
        #expect(project.retentionImageURLs(name: "Cancel").map(\.lastPathComponent) == ["Cancel.png"])
    }

    @Test func refusesAnImageThatIsNotAPNGOrAJPEG() throws {
        let project = try project()
        #expect(throws: ContentWriteError.self) {
            try ContentWriter.setRetentionImage(from: URL(fileURLWithPath: "/tmp/a.gif"), message: "Cancel", in: project)
        }
    }

    // MARK: - Pull

    @Test func pullTakesTheShippedLanguagesAsNeedsHuman() throws {
        let remote = RemoteRetentionMessage(
            id: "m1", referenceName: "Cancel",
            version: RemoteRetentionVersion(
                id: "v1", state: .prepareForSubmission,
                words: [
                    "en-US": RemoteRetentionWords(id: "w1", header: "Stay", body: "More soon"),
                    "fr-FR": RemoteRetentionWords(id: "w2", header: "Reste", body: "Bientot")
                ],
                placementID: nil
            )
        )
        let project = try project()
        let outcome = try RetentionSnapshot.write([remote], to: project)
        #expect(outcome.written == ["Cancel"])

        let message = try #require(ProductStore.load(in: project).retentionMessages["Cancel"])
        #expect(message.status == .needsHuman)
        #expect(message.localizations.keys.sorted() == ["en-US"])

        let again = try RetentionSnapshot.write([remote], to: project)
        #expect(again.left == ["Cancel"])
    }

    @Test func theProductSnapshotWritesTheMessagesToo() throws {
        let project = try project()
        let remote = RemoteProducts(appID: "app", products: [], groupNames: [:], retentionMessages: [
            RemoteRetentionMessage(id: "m1", referenceName: "Cancel", version: nil)
        ])
        let outcome = try ProductSnapshot.write(remote, to: project)
        #expect(outcome.writtenRetentionMessages == ["Cancel"])
        #expect(ProductStore.load(in: project).retentionMessages["Cancel"] != nil)
    }
}
