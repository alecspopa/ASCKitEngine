import Foundation

/// One app preview on disk, with what its file says about it.
public struct PreviewFile: Sendable, Hashable, Identifiable {
    public let url: URL
    public let fileName: String
    public let byteCount: Int

    /// The size the video shows at, after the rotation in its track header.
    /// Nil when the file could not be read as a movie.
    public let pixelWidth: Int?
    public let pixelHeight: Int?

    /// In seconds.
    public let duration: Double?

    /// Frames per second, from the sample table. Nil for a fragmented file,
    /// which keeps its samples outside the header.
    public let frameRate: Double?

    /// The four characters of the video codec, such as `avc1` or `apch`.
    public let videoCodec: String?
    public let hasAudio: Bool?

    /// A movie split into fragments, which a check cannot read all of.
    public let isFragmented: Bool

    /// The frame App Store Connect shows before the video plays, from
    /// `poster-frames.json` next to it. Nil leaves Apple's choice.
    public var posterFrame: String?

    public var id: URL { url }

    public init(
        url: URL,
        fileName: String,
        byteCount: Int,
        pixelWidth: Int? = nil,
        pixelHeight: Int? = nil,
        duration: Double? = nil,
        frameRate: Double? = nil,
        videoCodec: String? = nil,
        hasAudio: Bool? = nil,
        isFragmented: Bool = false,
        posterFrame: String? = nil
    ) {
        self.url = url
        self.fileName = fileName
        self.byteCount = byteCount
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.duration = duration
        self.frameRate = frameRate
        self.videoCodec = videoCodec
        self.hasAudio = hasAudio
        self.isFragmented = isFragmented
        self.posterFrame = posterFrame
    }

    public var isReadable: Bool { pixelWidth != nil && pixelHeight != nil && duration != nil }
}

/// Reads a QuickTime or MPEG-4 file's header without decoding a frame.
///
/// Synchronous on purpose. Reading a project's files is synchronous, from the
/// check in a git hook to the window, and AVFoundation's readers are async.
/// Only the `moov` box is read, so a 500 MB file costs a few kilobytes.
public enum VideoInspector {
    public static func inspect(url: URL) -> PreviewFile {
        let byteCount = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let unreadable = PreviewFile(url: url, fileName: url.lastPathComponent, byteCount: byteCount)

        guard let handle = try? FileHandle(forReadingFrom: url) else { return unreadable }
        defer { try? handle.close() }
        guard let top = try? Box.children(of: handle, from: 0, to: UInt64(byteCount)),
              let moovBox = top.first(where: { $0.type == "moov" }),
              let moov = try? handle.read(moovBox)
        else { return unreadable }

        let isFragmented = top.contains { $0.type == "moof" } || Box.find("mvex", in: moov) != nil
        guard let movie = MovieHeader(moov) else { return unreadable }

        var video: Track?
        var hasAudio = false
        for trak in Box.all("trak", in: moov) {
            guard let track = Track(trak) else { continue }
            if track.handler == "vide", video == nil { video = track }
            if track.handler == "soun" { hasAudio = true }
        }
        guard let video else { return unreadable }

        let duration = movie.seconds ?? video.seconds
        return PreviewFile(
            url: url,
            fileName: url.lastPathComponent,
            byteCount: byteCount,
            pixelWidth: video.displayWidth,
            pixelHeight: video.displayHeight,
            duration: duration,
            frameRate: isFragmented ? nil : video.frameRate,
            videoCodec: video.codec,
            hasAudio: hasAudio,
            isFragmented: isFragmented
        )
    }
}

// MARK: - Boxes

/// One box of an ISO base media file: its type, and where its body is.
struct Box {
    let type: String
    let bodyStart: Int
    let bodyEnd: Int

    /// The boxes at one level of a file, by their headers alone.
    static func children(of handle: FileHandle, from start: UInt64, to end: UInt64) throws -> [FileBox] {
        var boxes: [FileBox] = []
        var offset = start
        while offset + 8 <= end {
            try handle.seek(toOffset: offset)
            guard let header = try handle.read(upToCount: 16), header.count >= 8 else { break }
            var size = UInt64(header.uint32(at: 0))
            let type = header.fourCC(at: 4)
            var headerLength: UInt64 = 8
            if size == 1, header.count >= 16 {
                size = header.uint64(at: 8)
                headerLength = 16
            } else if size == 0 {
                size = end - offset
            }
            guard size >= headerLength, offset + size <= end else { break }
            boxes.append(FileBox(type: type, start: offset + headerLength, end: offset + size))
            offset += size
        }
        return boxes
    }

    /// The boxes at one level of bytes already read.
    static func children(in data: Data, from start: Int = 0, to end: Int? = nil) -> [Box] {
        var boxes: [Box] = []
        var offset = start
        let end = min(end ?? data.count, data.count)
        while offset + 8 <= end {
            var size = Int(data.uint32(at: offset))
            let type = data.fourCC(at: offset + 4)
            var headerLength = 8
            if size == 1, offset + 16 <= end {
                size = Int(data.uint64(at: offset + 8))
                headerLength = 16
            } else if size == 0 {
                size = end - offset
            }
            guard size >= headerLength, offset + size <= end else { break }
            boxes.append(Box(type: type, bodyStart: offset + headerLength, bodyEnd: offset + size))
            offset += size
        }
        return boxes
    }

    /// The first box of a type, looking through the boxes that hold others.
    static func find(_ type: String, in data: Data, from start: Int = 0, to end: Int? = nil) -> Box? {
        for box in children(in: data, from: start, to: end) {
            if box.type == type { return box }
            if containers.contains(box.type), let found = find(type, in: data, from: box.bodyStart, to: box.bodyEnd) {
                return found
            }
        }
        return nil
    }

    static func all(_ type: String, in data: Data) -> [Data] {
        children(in: data).filter { $0.type == type }.map { data.subdata(in: $0.bodyStart ..< $0.bodyEnd) }
    }

    private static let containers: Set = ["moov", "trak", "mdia", "minf", "stbl", "mvex", "edts"]
}

struct FileBox {
    let type: String
    let start: UInt64
    let end: UInt64
}

private extension FileHandle {
    func read(_ box: FileBox) throws -> Data? {
        try seek(toOffset: box.start)
        return try read(upToCount: Int(box.end - box.start))
    }
}

// MARK: - What the boxes say

struct MovieHeader {
    let timescale: UInt32
    let duration: UInt64

    init?(_ moov: Data) {
        guard let box = Box.find("mvhd", in: moov), box.bodyEnd - box.bodyStart >= 20 else { return nil }
        let at = box.bodyStart
        if moov[at] == 1 {
            guard box.bodyEnd - at >= 32 else { return nil }
            timescale = moov.uint32(at: at + 20)
            duration = moov.uint64(at: at + 24)
        } else {
            timescale = moov.uint32(at: at + 12)
            duration = UInt64(moov.uint32(at: at + 16))
        }
    }

    var seconds: Double? {
        guard timescale > 0, duration > 0 else { return nil }
        return Double(duration) / Double(timescale)
    }
}

struct Track {
    let handler: String
    let width: Int
    let height: Int
    let isTurned: Bool
    let timescale: UInt32
    let duration: UInt64
    let codec: String?
    let sampleCount: UInt64

    init?(_ trak: Data) {
        guard let tkhd = Box.find("tkhd", in: trak),
              let mdhd = Box.find("mdhd", in: trak),
              let hdlr = Box.find("hdlr", in: trak), hdlr.bodyEnd - hdlr.bodyStart >= 12
        else { return nil }

        // The matrix and the size sit at the end of the track header, after
        // fields whose length depends on its version.
        let tkhdEnd = tkhd.bodyEnd
        guard tkhdEnd - tkhd.bodyStart >= 84 else { return nil }
        width = Int(trak.uint32(at: tkhdEnd - 8) >> 16)
        height = Int(trak.uint32(at: tkhdEnd - 4) >> 16)
        let matrixStart = tkhdEnd - 44
        let scaleX = Int32(bitPattern: trak.uint32(at: matrixStart))
        let shearY = Int32(bitPattern: trak.uint32(at: matrixStart + 4))
        isTurned = scaleX == 0 && shearY != 0

        let at = mdhd.bodyStart
        guard mdhd.bodyEnd - at >= 20 else { return nil }
        if trak[at] == 1 {
            guard mdhd.bodyEnd - at >= 32 else { return nil }
            timescale = trak.uint32(at: at + 20)
            duration = trak.uint64(at: at + 24)
        } else {
            timescale = trak.uint32(at: at + 12)
            duration = UInt64(trak.uint32(at: at + 16))
        }

        handler = trak.fourCC(at: hdlr.bodyStart + 8)

        if let stsd = Box.find("stsd", in: trak), stsd.bodyEnd - stsd.bodyStart >= 16 {
            codec = trak.fourCC(at: stsd.bodyStart + 12)
        } else {
            codec = nil
        }

        var samples: UInt64 = 0
        if let stts = Box.find("stts", in: trak), stts.bodyEnd - stts.bodyStart >= 8 {
            let entries = Int(trak.uint32(at: stts.bodyStart + 4))
            for index in 0 ..< entries {
                let entry = stts.bodyStart + 8 + index * 8
                guard entry + 8 <= stts.bodyEnd else { break }
                samples += UInt64(trak.uint32(at: entry))
            }
        }
        sampleCount = samples
    }

    var displayWidth: Int { isTurned ? height : width }
    var displayHeight: Int { isTurned ? width : height }

    var seconds: Double? {
        guard timescale > 0, duration > 0 else { return nil }
        return Double(duration) / Double(timescale)
    }

    /// The average over the whole track, which for a variable frame rate is
    /// what App Store Connect compares with its range.
    var frameRate: Double? {
        guard let seconds, sampleCount > 0 else { return nil }
        return Double(sampleCount) / seconds
    }
}

// MARK: - Reading numbers

private extension Data {
    func uint32(at offset: Int) -> UInt32 {
        guard offset >= 0, offset + 4 <= count else { return 0 }
        let start = startIndex + offset
        return self[start ..< start + 4].reduce(0) { $0 << 8 | UInt32($1) }
    }

    func uint64(at offset: Int) -> UInt64 {
        guard offset >= 0, offset + 8 <= count else { return 0 }
        let start = startIndex + offset
        return self[start ..< start + 8].reduce(0) { $0 << 8 | UInt64($1) }
    }

    func fourCC(at offset: Int) -> String {
        guard offset >= 0, offset + 4 <= count else { return "" }
        let start = startIndex + offset
        return String(bytes: self[start ..< start + 4], encoding: .isoLatin1) ?? ""
    }
}
