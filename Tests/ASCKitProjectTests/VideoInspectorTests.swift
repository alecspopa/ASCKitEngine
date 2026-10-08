import AVFoundation
import Foundation
import Testing
@testable import ASCKitProject

/// Movies are written once and shared, because each one takes a moment.
actor Movies {
    static let shared = Movies()

    /// One task for each movie, so two tests asking at once wait for the
    /// same write instead of starting a second one over the first.
    private var made: [String: Task<URL, any Error>] = [:]
    private let folder = FixtureProject.fixturesRoot.appending(path: "movies-\(ProcessInfo.processInfo.processIdentifier)")

    func movie(_ name: String, _ options: MovieWriter.Options = MovieWriter.Options()) async throws -> URL {
        if let task = made[name] { return try await task.value }
        let url = folder.appending(path: name)
        let folder = folder
        let task = Task {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try await MovieWriter.write(to: url, options)
            return url
        }
        made[name] = task
        return try await task.value
    }
}

@Suite(.serialized)
struct VideoInspectorTests {
    @Test func readsTheSizeLengthRateAndCodecOfAnH264Movie() async throws {
        let url = try await Movies.shared.movie("h264.mov")
        let file = VideoInspector.inspect(url: url)

        #expect(file.isReadable)
        #expect(file.pixelWidth == 64)
        #expect(file.pixelHeight == 128)
        #expect(try abs(#require(file.duration) - 16) < 0.1)
        #expect(try abs(#require(file.frameRate) - 30) < 0.5)
        #expect(file.videoCodec == "avc1")
        #expect(file.hasAudio == false)
        #expect(file.isFragmented == false)
        #expect(file.byteCount > 0)
    }

    @Test func readsAnMP4TheSameWay() async throws {
        let url = try await Movies.shared.movie("h264.mp4", MovieWriter.Options(fileType: .mp4))
        let file = VideoInspector.inspect(url: url)
        #expect(file.videoCodec == "avc1")
        #expect(file.pixelWidth == 64)
    }

    @Test func readsProRes422HQ() async throws {
        let url = try await Movies.shared.movie("prores.mov", MovieWriter.Options(seconds: 1, codec: .proRes422HQ))
        #expect(VideoInspector.inspect(url: url).videoCodec == "apch")
    }

    @Test func readsTheSizeATurnedTrackShowsAt() async throws {
        let url = try await Movies.shared.movie("turned.mov", MovieWriter.Options(seconds: 1, turned: true))
        let file = VideoInspector.inspect(url: url)
        #expect(file.pixelWidth == 128)
        #expect(file.pixelHeight == 64)
    }

    /// A second copy of the video track, marked as sound. The reader looks at
    /// the handler, so this is what an audio track is to it.
    @Test func findsTheAudioTrack() async throws {
        let movie = try await Data(contentsOf: Movies.shared.movie("h264.mov"))
        let url = try write(Array(MovieBytes.withSoundTrack(movie)), named: "audio.mov")

        let file = VideoInspector.inspect(url: url)
        #expect(file.hasAudio == true)
        #expect(file.pixelWidth == 64, "the video track is still the first one")
    }

    @Test func readsTheAverageRateOfAWanderingFrameRate() async throws {
        let url = try await Movies.shared.movie("vfr.mov", MovieWriter.Options(seconds: 4, variableFrameRate: true))
        let rate = try #require(VideoInspector.inspect(url: url).frameRate)
        #expect(rate > 28 && rate < 31)
    }

    /// AVFoundation joins the fragments when it finishes, so the fragment is
    /// added by hand: a `moof` box after the movie.
    @Test func readsNoRateFromAFragmentedMovie() async throws {
        let movie = try await Data(contentsOf: Movies.shared.movie("h264.mp4", MovieWriter.Options(fileType: .mp4)))
        let url = try write(Array(movie) + [0, 0, 0, 8] + Array("moof".utf8), named: "fragmented.mp4")
        let file = VideoInspector.inspect(url: url)
        #expect(file.isFragmented)
        #expect(file.frameRate == nil)
        #expect(file.pixelWidth == 64)
    }

    @Test(arguments: [1.0, 15.0, 30.0])
    func readsTheLength(seconds: Double) async throws {
        let url = try await Movies.shared.movie("len-\(seconds).mov", MovieWriter.Options(seconds: seconds))
        #expect(try abs(#require(VideoInspector.inspect(url: url).duration) - seconds) < 0.1)
    }

    // MARK: - Files that are not movies

    func write(_ bytes: [UInt8], named name: String) throws -> URL {
        let url = FixtureProject.fixturesRoot.appending(path: "\(UUID().uuidString)-\(name)")
        try Data(bytes).write(to: url)
        return url
    }

    @Test func readsNothingFromAnEmptyFile() throws {
        let file = try VideoInspector.inspect(url: write([], named: "empty.mov"))
        #expect(file.isReadable == false)
        #expect(file.byteCount == 0)
    }

    @Test func readsNothingFromAFileThatIsNotAMovie() throws {
        let png: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A] + Array(repeating: 0, count: 64)
        #expect(try VideoInspector.inspect(url: write(png, named: "not.mov")).isReadable == false)
    }

    @Test func readsNothingFromAMovieCutOffInItsHeader() async throws {
        let whole = try await Data(contentsOf: Movies.shared.movie("h264.mov"))
        let cut = try write(Array(whole.prefix(whole.count / 50)), named: "cut.mov")
        let file = VideoInspector.inspect(url: cut)
        #expect(file.isReadable == false || file.pixelWidth == 64, "never a crash, and never a wrong size")
    }

    @Test func readsNothingFromAHeaderThatSaysItIsLongerThanTheFile() throws {
        // A moov box that claims 4 GB.
        let bytes: [UInt8] = [0xFF, 0xFF, 0xFF, 0xF0, 0x6D, 0x6F, 0x6F, 0x76] + Array(repeating: 0, count: 32)
        #expect(try VideoInspector.inspect(url: write(bytes, named: "liar.mov")).isReadable == false)
    }

    @Test func readsNothingFromAFileThatDoesNotExist() {
        let file = VideoInspector.inspect(url: URL(fileURLWithPath: "/nonexistent/preview.mov"))
        #expect(file.isReadable == false)
    }
}

/// Edits a movie's bytes the way a real file can differ.
enum MovieBytes {
    /// The movie with its first track copied, the copy's handler set to sound.
    static func withSoundTrack(_ movie: Data) throws -> Data {
        let top = Box.children(in: movie)
        let moovBox = try #require(top.first { $0.type == "moov" })
        let moov = movie.subdata(in: moovBox.bodyStart ..< moovBox.bodyEnd)
        let trakBox = try #require(Box.children(in: moov).first { $0.type == "trak" })
        var trak = moov.subdata(in: (trakBox.bodyStart - 8) ..< trakBox.bodyEnd)

        let handler = try #require(trak.range(of: Data("vide".utf8)))
        trak.replaceSubrange(handler, with: Data("soun".utf8))

        var newMoov = moov
        newMoov.append(trak)
        var header = Data()
        let size = UInt32(newMoov.count + 8)
        header.append(contentsOf: [UInt8(size >> 24), UInt8(size >> 16 & 0xFF), UInt8(size >> 8 & 0xFF), UInt8(size & 0xFF)])
        header.append(contentsOf: Array("moov".utf8))

        var result = movie.subdata(in: 0 ..< (moovBox.bodyStart - 8))
        result.append(header + newMoov)
        result.append(movie.subdata(in: moovBox.bodyEnd ..< movie.count))
        return result
    }
}
