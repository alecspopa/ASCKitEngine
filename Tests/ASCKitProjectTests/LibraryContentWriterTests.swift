import ASCKitAPI
import Foundation
import Testing
@testable import ASCKitProject

struct LibraryContentWriterTests {
    let fixture: FixtureProject
    let project: Project

    init() throws {
        fixture = try FixtureProject()
        try fixture.writeConfig(ProjectConfig(bundleID: "b", keyID: "K", issuerID: "I", locales: ["en-US"]))
        project = try fixture.load()
    }

    func source(_ name: String, contents: String? = nil) throws -> URL {
        let folder = fixture.rootURL.appending(path: "inbox")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: name)
        try Data((contents ?? name).utf8).write(to: url)
        return url
    }

    func add(_ names: [String]) throws -> [PreviewFile] {
        try LibraryContentWriter.addPreviews(
            from: names.map { try source($0) }, locale: "en-US", deviceClass: .iPhone69, at: .version("1.0"), in: project
        )
    }

    var folder: URL { project.previewsURL(version: "1.0", locale: "en-US", deviceClassID: "iphone-6.9") }

    // MARK: - Previews

    @Test func addsVideosInFileNameOrder() throws {
        defer { fixture.remove() }
        #expect(try add(["02-b.mov", "01-a.mp4"]).map(\.fileName) == ["01-a.mp4", "02-b.mov"])
    }

    @Test func refusesAFileThatIsNotAVideoAndAddsNothing() throws {
        defer { fixture.remove() }
        #expect(throws: LibraryWriteError.notAVideo("02-b.png")) { try add(["01-a.mov", "02-b.png"]) }
        #expect(LibraryContentWriter.previews(in: folder).isEmpty)
    }

    @Test func refusesAFourthPreview() throws {
        defer { fixture.remove() }
        _ = try add(["01.mov", "02.mov", "03.mov"])
        #expect(throws: LibraryWriteError.tooManyPreviews(limit: 3)) { try add(["04.mov"]) }
    }

    @Test func refusesANameTheSetHas() throws {
        defer { fixture.remove() }
        _ = try add(["01.mov"])
        #expect(throws: LibraryWriteError.nameTaken("01.mov")) { try add(["01.mov"]) }
    }

    @Test func refusesAPreviewForAWatch() throws {
        defer { fixture.remove() }
        #expect(throws: LibraryWriteError.takesNoPreviews("watch-ultra")) {
            try LibraryContentWriter.addPreviews(from: [source("01.mov")], locale: "en-US",
                                                 deviceClass: .watchUltra, at: .version("1.0"), in: project)
        }
    }

    @Test func reordersAndKeepsEachPosterFrameWithItsVideo() throws {
        defer { fixture.remove() }
        _ = try add(["01-a.mov", "02-b.mov"])
        try PosterFrames.save(["01-a.mov": "00:00:01:00"], in: folder)

        let files = try LibraryContentWriter.reorderPreviews(
            order: ["02-b.mov", "01-a.mov"], locale: "en-US", deviceClass: .iPhone69, at: .version("1.0"), in: project
        )

        #expect(files.map(\.fileName) == ["01-b.mov", "02-a.mov"])
        #expect(PosterFrames.load(in: folder) == ["02-a.mov": "00:00:01:00"])
        #expect(try String(contentsOf: folder.appending(path: "01-b.mov"), encoding: .utf8) == "02-b.mov")
    }

    @Test(arguments: [["01-a.mov"], ["01-a.mov", "01-a.mov"], ["01-a.mov", "gone.mov"]])
    func refusesAnOrderThatDoesNotNameEveryFileOnce(order: [String]) throws {
        defer { fixture.remove() }
        _ = try add(["01-a.mov", "02-b.mov"])
        #expect(throws: LibraryWriteError.orderNamesEveryFile) {
            try LibraryContentWriter.reorderPreviews(order: order, locale: "en-US", deviceClass: .iPhone69,
                                                     at: .version("1.0"), in: project)
        }
    }

    @Test func removesAPreviewAndItsPosterFrame() throws {
        defer { fixture.remove() }
        _ = try add(["01-a.mov", "02-b.mov"])
        try PosterFrames.save(["01-a.mov": "00:00:01:00", "02-b.mov": "00:00:02:00"], in: folder)

        let files = try LibraryContentWriter.removePreviews(named: ["01-a.mov"], locale: "en-US",
                                                            deviceClass: .iPhone69, at: .version("1.0"), in: project)

        #expect(files.map(\.fileName) == ["02-b.mov"])
        #expect(PosterFrames.load(in: folder) == ["02-b.mov": "00:00:02:00"])
    }

    @Test func refusesToRemoveAFileThatIsNotThere() throws {
        defer { fixture.remove() }
        #expect(throws: LibraryWriteError.noSuchFile("gone.mov")) {
            try LibraryContentWriter.removePreviews(named: ["gone.mov"], locale: "en-US", deviceClass: .iPhone69,
                                                    at: .version("1.0"), in: project)
        }
    }

    @Test func setsAndClearsAPosterFrame() async throws {
        defer { fixture.remove() }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try await FileManager.default.copyItem(at: Movies.shared.movie("h264.mov"), to: folder.appending(path: "01-a.mov"))

        let set = try LibraryContentWriter.setPosterFrame("00:00:03:00", for: "01-a.mov", locale: "en-US",
                                                          deviceClass: .iPhone69, at: .version("1.0"), in: project)
        #expect(set.first?.posterFrame == "00:00:03:00")

        let cleared = try LibraryContentWriter.setPosterFrame(nil, for: "01-a.mov", locale: "en-US",
                                                              deviceClass: .iPhone69, at: .version("1.0"), in: project)
        #expect(cleared.first?.posterFrame == nil)
        #expect(FileManager.default.fileExists(atPath: folder.appending(path: PosterFrames.fileName).path) == false)
    }

    @Test(arguments: ["00:00:17:00", "5s", "00:00:03:31"])
    func refusesAPosterFrameOutsideTheVideo(timeCode: String) async throws {
        defer { fixture.remove() }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try await FileManager.default.copyItem(at: Movies.shared.movie("h264.mov"), to: folder.appending(path: "01-a.mov"))

        #expect(throws: LibraryWriteError.badTimeCode(timeCode)) {
            try LibraryContentWriter.setPosterFrame(timeCode, for: "01-a.mov", locale: "en-US",
                                                    deviceClass: .iPhone69, at: .version("1.0"), in: project)
        }
    }

    // MARK: - Header and search results

    @Test func putsInTheArtUnderTheNameOfItsRole() throws {
        defer { fixture.remove() }
        let file = try LibraryContentWriter.setCreative(from: source("hero.PNG"), role: .header, locale: "en-US",
                                                        at: .version("1.0"), in: project)
        #expect(file.fileName == "header.png")
    }

    @Test func replacesTheArtOfARoleWhateverItsKind() throws {
        defer { fixture.remove() }
        _ = try LibraryContentWriter.setCreative(from: source("hero.png"), role: .header, locale: "en-US",
                                                 at: .version("1.0"), in: project)
        _ = try LibraryContentWriter.setCreative(from: source("hero.mov"), role: .header, locale: "en-US",
                                                 at: .version("1.0"), in: project)

        let folder = CreativeFolder.load(from: project.creativeURL(version: "1.0"))
        #expect(folder.files["en-US"]?[.header]?.map(\.fileName) == ["header.mov"])
    }

    @Test func leavesTheOtherRoleAlone() throws {
        defer { fixture.remove() }
        _ = try LibraryContentWriter.setCreative(from: source("a.png"), role: .header, locale: "en-US",
                                                 at: .version("1.0"), in: project)
        _ = try LibraryContentWriter.setCreative(from: source("b.png"), role: .searchResults, locale: "en-US",
                                                 at: .version("1.0"), in: project)
        try LibraryContentWriter.removeCreative(role: .header, locale: "en-US", at: .version("1.0"), in: project)

        let folder = CreativeFolder.load(from: project.creativeURL(version: "1.0"))
        #expect(folder.file(locale: "en-US", role: .header) == nil)
        #expect(folder.file(locale: "en-US", role: .searchResults) != nil)
    }

    @Test func refusesAFileThatIsNotArt() throws {
        defer { fixture.remove() }
        #expect(throws: LibraryWriteError.notArt("notes.txt")) {
            try LibraryContentWriter.setCreative(from: source("notes.txt"), role: .header, locale: "en-US",
                                                 at: .version("1.0"), in: project)
        }
    }

    // MARK: - A treatment

    /// The treatment folder holds its previews where the test reader looks.
    @Test func addsPreviewsToATreatment() throws {
        defer { fixture.remove() }
        let place = LibraryContentPlace.treatment(experiment: "Bigger buttons", treatment: "Treatment A")

        let added = try LibraryContentWriter.addPreviews(
            from: [source("01-a.mov")], locale: "en-US", deviceClass: .iPhone69, at: place, in: project
        )

        #expect(added.map(\.fileName) == ["01-a.mov"])
        let slot = ExperimentSlot(
            experiment: "Bigger buttons", treatment: "Treatment A", locale: "en-US", deviceClassID: "iphone-6.9"
        )
        #expect(ExperimentContentStore.load(in: project).previews(in: slot).map(\.fileName) == ["01-a.mov"])
        #expect(LibraryContentWriter.previews(in: folder).isEmpty)
    }

    @Test func putsArtInATreatmentAndTakesItOut() throws {
        defer { fixture.remove() }
        let place = LibraryContentPlace.treatment(experiment: "Bigger buttons", treatment: "Treatment A")

        _ = try LibraryContentWriter.setCreative(
            from: source("art.png"), role: .header, locale: "en-US", at: place, in: project
        )
        let art = ExperimentContentStore.load(in: project).creative["Bigger buttons/Treatment A"]
        #expect(art?.file(locale: "en-US", role: .header)?.fileName == "header.png")

        try LibraryContentWriter.removeCreative(role: .header, locale: "en-US", at: place, in: project)
        #expect(ExperimentContentStore.load(in: project).creative["Bigger buttons/Treatment A"] == nil)
    }

    @Test func keepsATreatmentsPreviewsOutOfItsLanguages() {
        let place = LibraryContentPlace.treatment(experiment: "T", treatment: "A")
        let url = project.previewsURL(place, locale: "en-US", deviceClassID: "iphone-6.9")
        #expect(url.path.hasSuffix("product-page-optimization/T/A/previews/en-US/iphone-6.9"))
        #expect(project.creativeURL(place, locale: "en-US").path.hasSuffix("product-page-optimization/T/A/creative/en-US"))
        fixture.remove()
    }

    @Test func removesNothingWithoutComplaint() throws {
        defer { fixture.remove() }
        try LibraryContentWriter.removeCreative(role: .header, locale: "en-US", at: .version("1.0"), in: project)
    }
}
