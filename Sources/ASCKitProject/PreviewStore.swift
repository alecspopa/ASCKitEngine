import Foundation

// MARK: - Poster frames

/// The poster frame of each preview in one folder, by file name, from an
/// optional `poster-frames.json` beside them:
///
/// ```json
/// { "01-onboarding-iPhone-6.9-en_US.mov": "00:00:05:00" }
/// ```
public enum PosterFrames {
    public static let fileName = "poster-frames.json"

    /// Empty when there is no file. Nil when the file is there and is not a
    /// map of names to strings, which a check reports.
    public static func load(in folder: URL) -> [String: String]? {
        let url = folder.appending(path: fileName)
        guard let data = try? Data(contentsOf: url) else { return [:] }
        return try? JSONDecoder().decode([String: String].self, from: data)
    }

    public static func save(_ frames: [String: String], in folder: URL) throws {
        let url = folder.appending(path: fileName)
        guard frames.isEmpty == false else {
            try? FileManager.default.removeItem(at: url)
            return
        }
        try ProjectJSON.write(frames, to: url, atomic: true)
    }

    /// The seconds a time code such as `00:00:05:00` stands for: hours,
    /// minutes, seconds and frames. Nil when it is not written that way.
    public static func seconds(of timeCode: String, frameRate: Double = 30) -> Double? {
        let parts = timeCode.split(separator: ":").map { Int($0) }
        guard parts.count == 4, let hours = parts[0], let minutes = parts[1],
              let seconds = parts[2], let frames = parts[3],
              hours >= 0, (0 ..< 60).contains(minutes), (0 ..< 60).contains(seconds), frames >= 0,
              Double(frames) < max(frameRate, 1)
        else { return nil }
        return Double(hours * 3600 + minutes * 60 + seconds) + Double(frames) / max(frameRate, 1)
    }

    /// The time code of the frame shown at this many seconds. A time between
    /// two frames gives the earlier frame.
    public static func timeCode(atSeconds seconds: Double, frameRate: Double = 30) -> String {
        let rate = max(frameRate, 1)
        let totalFrames = Int((max(seconds, 0) * rate + 0.000_1).rounded(.down))
        let framesPerSecond = Int(rate.rounded(.up))
        let whole = totalFrames / framesPerSecond
        let frames = totalFrames % framesPerSecond
        return String(format: "%02d:%02d:%02d:%02d", whole / 3600, whole / 60 % 60, whole % 60, frames)
    }
}

// MARK: - Reading previews

/// The app previews in one folder of `<locale>/<device class>/` folders.
public struct PreviewFolder: Sendable {
    public var previews: [ScreenshotSlot: [PreviewFile]] = [:]

    /// The slots whose `poster-frames.json` could not be read.
    public var unreadablePosterFrames: Set<ScreenshotSlot> = []

    /// What each slot's `poster-frames.json` names, including files that are
    /// not there, which a check reports.
    public var posterFrames: [ScreenshotSlot: [String: String]] = [:]

    public init() {}

    public static func load(from root: URL) -> PreviewFolder {
        var folder = PreviewFolder()
        for localeDirectory in DirectoryListing.directories(in: root) {
            for deviceDirectory in DirectoryListing.directories(in: localeDirectory) {
                let slot = ScreenshotSlot(locale: localeDirectory.lastPathComponent,
                                          deviceClassID: deviceDirectory.lastPathComponent)
                let frames = PosterFrames.load(in: deviceDirectory)
                if frames == nil { folder.unreadablePosterFrames.insert(slot) }
                if let frames, frames.isEmpty == false { folder.posterFrames[slot] = frames }

                folder.previews[slot] = DirectoryListing.files(in: deviceDirectory, keys: fileKeys, ignoring: ignoredFileNames).map { url in
                    var file = VideoInspector.inspect(url: url)
                    file.posterFrame = frames?[url.lastPathComponent]
                    return file
                }
            }
        }
        return folder
    }

    public func previews(locale: String, deviceClassID: String) -> [PreviewFile] {
        previews[ScreenshotSlot(locale: locale, deviceClassID: deviceClassID)] ?? []
    }

    private static let ignoredFileNames: Set = [PosterFrames.fileName]
    private static let fileKeys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey]
}

public extension Project {
    /// `versions/<version>/previews`, beside the screenshots.
    func previewsURL(version: String) -> URL {
        versionsURL.appending(path: version).appending(path: "previews")
    }

    func previewsURL(version: String, locale: String, deviceClassID: String) -> URL {
        previewsURL(version: version).appending(path: locale).appending(path: deviceClassID)
    }
}
