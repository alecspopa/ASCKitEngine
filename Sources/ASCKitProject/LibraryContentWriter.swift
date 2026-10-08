import Foundation

/// Writes the app previews and the header and search results art of a
/// version or of a Product Page Optimization treatment. Every caller writes
/// through here, so each leaves the same files behind.
public enum LibraryContentWriter {
    static let videoExtensions: Set = ["mov", "mp4", "m4v"]

    // MARK: - Previews

    /// Copies videos into a slot, after the ones there. The whole call is
    /// refused when one file is not a video, a name is taken, or the slot
    /// would hold more than App Store Connect takes.
    public static func addPreviews(
        from urls: [URL],
        locale: String,
        deviceClass: DeviceClass,
        at place: LibraryContentPlace,
        in project: Project
    ) throws -> [PreviewFile] {
        guard deviceClass.takesPreviews else { throw LibraryWriteError.takesNoPreviews(deviceClass.id) }
        let folder = project.previewsURL(place, locale: locale, deviceClassID: deviceClass.id)
        let existing = previews(in: folder)

        for url in urls where videoExtensions.contains(url.pathExtension.lowercased()) == false {
            throw LibraryWriteError.notAVideo(url.lastPathComponent)
        }
        guard existing.count + urls.count <= VideoRules.maximumPerSet else {
            throw LibraryWriteError.tooManyPreviews(limit: VideoRules.maximumPerSet)
        }
        let taken = Set(existing.map(\.fileName))
        for url in urls where taken.contains(url.lastPathComponent) {
            throw LibraryWriteError.nameTaken(url.lastPathComponent)
        }

        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for url in urls {
            try FileManager.default.copyItem(at: url, to: folder.appending(path: url.lastPathComponent))
        }
        return previews(in: folder)
    }

    /// Puts the previews in this order by the number at the start of each
    /// name, and keeps their poster frames.
    public static func reorderPreviews(
        order: [String],
        locale: String,
        deviceClass: DeviceClass,
        at place: LibraryContentPlace,
        in project: Project
    ) throws -> [PreviewFile] {
        let folder = project.previewsURL(place, locale: locale, deviceClassID: deviceClass.id)
        let existing = previews(in: folder)
        guard Set(order) == Set(existing.map(\.fileName)), order.count == existing.count else {
            throw LibraryWriteError.orderNamesEveryFile
        }

        var frames = PosterFrames.load(in: folder) ?? [:]
        var renamed: [(from: URL, to: String)] = []
        for (index, name) in order.enumerated() {
            let wanted = ScreenshotRenumbering.fileName(
                position: index + 1,
                nameWithoutNumber: ScreenshotRenumbering.nameWithoutNumber(of: name),
                extension: (name as NSString).pathExtension
            )
            renamed.append((folder.appending(path: name), wanted))
        }

        // Through a temporary name first, so two files can swap places.
        var moved: [(URL, String)] = []
        for (from, wanted) in renamed {
            let staging = folder.appending(path: ".reorder-\(UUID().uuidString)-\(wanted)")
            try FileManager.default.moveItem(at: from, to: staging)
            moved.append((staging, wanted))
        }
        var newFrames: [String: String] = [:]
        for ((staging, wanted), (from, _)) in zip(moved, renamed) {
            try FileManager.default.moveItem(at: staging, to: folder.appending(path: wanted))
            if let frame = frames.removeValue(forKey: from.lastPathComponent) { newFrames[wanted] = frame }
        }
        try PosterFrames.save(newFrames.merging(frames) { kept, _ in kept }, in: folder)
        return previews(in: folder)
    }

    /// Moves the named previews to the Trash, and forgets their poster frames.
    public static func removePreviews(
        named names: [String],
        locale: String,
        deviceClass: DeviceClass,
        at place: LibraryContentPlace,
        in project: Project
    ) throws -> [PreviewFile] {
        let folder = project.previewsURL(place, locale: locale, deviceClassID: deviceClass.id)
        let existing = Set(previews(in: folder).map(\.fileName))
        for name in names where existing.contains(name) == false {
            throw LibraryWriteError.noSuchFile(name)
        }

        var frames = PosterFrames.load(in: folder) ?? [:]
        for name in names {
            try FileManager.default.trashItem(at: folder.appending(path: name), resultingItemURL: nil)
            frames[name] = nil
        }
        try PosterFrames.save(frames, in: folder)
        return previews(in: folder)
    }

    // swiftlint:disable function_parameter_count
    /// Sets the frame App Store Connect shows before a video plays. Nil goes
    /// back to App Store Connect's choice.
    public static func setPosterFrame(
        _ timeCode: String?,
        for name: String,
        locale: String,
        deviceClass: DeviceClass,
        at place: LibraryContentPlace,
        in project: Project
    ) throws -> [PreviewFile] {
        let folder = project.previewsURL(place, locale: locale, deviceClassID: deviceClass.id)
        guard let file = previews(in: folder).first(where: { $0.fileName == name }) else {
            throw LibraryWriteError.noSuchFile(name)
        }
        if let timeCode {
            guard let seconds = PosterFrames.seconds(of: timeCode, frameRate: file.frameRate ?? 30),
                  file.duration.map({ seconds <= $0 }) ?? true
            else { throw LibraryWriteError.badTimeCode(timeCode) }
        }

        var frames = PosterFrames.load(in: folder) ?? [:]
        frames[name] = timeCode
        try PosterFrames.save(frames, in: folder)
        return previews(in: folder)
    }

    // swiftlint:enable function_parameter_count

    static func previews(in folder: URL) -> [PreviewFile] {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        let frames = PosterFrames.load(in: folder) ?? [:]
        return names
            .filter { videoExtensions.contains(($0 as NSString).pathExtension.lowercased()) && $0.hasPrefix(".") == false }
            .sorted { $0.compare($1, options: .numeric) == .orderedAscending }
            .map { name in
                var file = VideoInspector.inspect(url: folder.appending(path: name))
                file.posterFrame = frames[name]
                return file
            }
    }

    // MARK: - Header and search results

    /// Puts a file in as the art for one role, in place of any there.
    public static func setCreative(
        from url: URL,
        role: CreativeRole,
        locale: String,
        at place: LibraryContentPlace,
        in project: Project
    ) throws -> CreativeFile {
        let ext = url.pathExtension.lowercased()
        guard CreativeFolder.imageExtensions.contains(ext) || CreativeFolder.videoExtensions.contains(ext) else {
            throw LibraryWriteError.notArt(url.lastPathComponent)
        }
        let folder = project.creativeURL(place, locale: locale)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try removeCreative(role: role, locale: locale, at: place, in: project)

        let target = folder.appending(path: "\(role.rawValue).\(ext)")
        try FileManager.default.copyItem(at: url, to: target)
        return CreativeFile.inspect(url: target)
    }

    /// Moves every file of one role to the Trash. Nothing there is no error.
    public static func removeCreative(
        role: CreativeRole, locale: String, at place: LibraryContentPlace, in project: Project
    ) throws {
        let folder = project.creativeURL(place, locale: locale)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        for name in names where (name as NSString).deletingPathExtension == role.rawValue {
            try FileManager.default.trashItem(at: folder.appending(path: name), resultingItemURL: nil)
        }
    }
}

public enum LibraryWriteError: Error, Equatable, CustomLocalizedStringResourceConvertible {
    case takesNoPreviews(String)
    case notAVideo(String)
    case notArt(String)
    case tooManyPreviews(limit: Int)
    case nameTaken(String)
    case noSuchFile(String)
    case orderNamesEveryFile
    case badTimeCode(String)

    public var localizedStringResource: LocalizedStringResource {
        switch self {
        case let .takesNoPreviews(deviceClass):
            LocalizedStringResource("App Store Connect takes no app preview for \(deviceClass).", bundle: .here)
        case let .notAVideo(name):
            LocalizedStringResource("\(name) is not a .mov, .mp4 or .m4v file.", bundle: .here)
        case let .notArt(name):
            LocalizedStringResource("\(name) is not a png, jpg, mov, mp4 or m4v file.", bundle: .here)
        case let .tooManyPreviews(limit):
            LocalizedStringResource("A set takes at most \(limit) app previews. Nothing was added.", bundle: .here)
        case let .nameTaken(name):
            LocalizedStringResource("The set already has a file called \(name). Nothing was added.", bundle: .here)
        case let .noSuchFile(name):
            LocalizedStringResource("The set has no file called \(name).", bundle: .here)
        case .orderNamesEveryFile:
            LocalizedStringResource("The order has to name every file in the set, once each.", bundle: .here)
        case let .badTimeCode(timeCode):
            LocalizedStringResource("""
            \(timeCode) is not a time code inside the video. Write it as hours, minutes, seconds and \
            frames, such as 00:00:05:00.
            """, bundle: .here)
        }
    }
}

extension LibraryWriteError: CustomStringConvertible {
    public var description: String { String(localized: localizedStringResource) }
}

// MARK: - Where the files go

/// A version, or a treatment of a draft test. Each holds its previews and its
/// art in the same layout.
public enum LibraryContentPlace: Sendable, Hashable {
    case version(String)
    case treatment(experiment: String, treatment: String)
}

public extension Project {
    func previewsURL(_ place: LibraryContentPlace, locale: String, deviceClassID: String) -> URL {
        let previews = switch place {
        case let .version(version):
            previewsURL(version: version)
        case let .treatment(experiment, treatment):
            experimentURL(experiment: experiment, treatment: treatment)
                .appending(path: ExperimentContentStore.previewsFolderName)
        }
        return previews.appending(path: locale).appending(path: deviceClassID)
    }

    func creativeURL(_ place: LibraryContentPlace, locale: String) -> URL {
        let creative = switch place {
        case let .version(version):
            creativeURL(version: version)
        case let .treatment(experiment, treatment):
            experimentURL(experiment: experiment, treatment: treatment).appending(path: CreativeFolder.folderName)
        }
        return creative.appending(path: locale)
    }
}
