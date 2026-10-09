import ASCKitAPI
import Foundation

// MARK: - What a preview group accepts

/// The video rules of one group, from the reference data when there is some
/// and from Apple's published specification when there is none.
public struct VideoRules: Sendable, Equatable {
    public let sizes: [AssetLibraryRefData.Dimensions]
    public let frameRates: ClosedRange<Double>
    public let duration: ClosedRange<Double>
    public let audioRequired: Bool
    public let maxFileSize: Int

    /// Lower case, with the dot.
    public let fileExtensions: [String]

    public static let maximumPerSet = 3

    public static func preview(of deviceClass: DeviceClass, refData: AssetLibraryRefData?) -> VideoRules {
        let specs = refData?.videoSpecs(type: .appPreview, group: deviceClass.placementGroup) ?? []
        guard specs.isEmpty == false else { return builtIn(deviceClass) }

        let rates = specs.flatMap { $0.frameRates ?? [] }
        let low = specs.compactMap { $0.duration?.min.flatMap(Self.seconds) }.min() ?? 15
        let high = specs.compactMap { $0.duration?.max.flatMap(Self.seconds) }.max() ?? 30
        return VideoRules(
            sizes: specs.compactMap(\.dimensions),
            frameRates: Double(rates.map(\.minFps).min() ?? 1) ... Double(rates.map(\.maxFps).max() ?? 30),
            duration: low ... max(low, high),
            audioRequired: specs.contains { $0.audioRequired == true },
            maxFileSize: specs.compactMap(\.maxFileSize).max() ?? 500 * 1024 * 1024,
            fileExtensions: Array(Set(specs.flatMap { $0.fileExtensions ?? [] }.map { $0.lowercased() })).sorted()
        )
    }

    /// Apple's app preview specification, for a check with no reference data.
    static func builtIn(_ deviceClass: DeviceClass) -> VideoRules {
        let size = switch deviceClass.family {
        case "iPad": (1200, 1600)
        case "Mac", "Apple TV": (1920, 1080)
        case "Apple Vision Pro": (3840, 2160)
        default: (886, 1920)
        }
        return VideoRules(
            sizes: [.init(minWidth: size.0, maxWidth: size.0, minHeight: size.1, maxHeight: size.1)],
            frameRates: 1 ... 30,
            duration: 15 ... 30,
            audioRequired: false,
            maxFileSize: 500 * 1024 * 1024,
            fileExtensions: [".m4v", ".mov", ".mp4"]
        )
    }

    /// An ISO 8601 duration such as `PT15S` or `PT1M`, in seconds.
    static func seconds(_ iso: String) -> Double? {
        guard iso.hasPrefix("PT") else { return nil }
        var total = 0.0
        var number = ""
        for character in iso.dropFirst(2) {
            if character.isNumber || character == "." {
                number.append(character)
                continue
            }
            guard let value = Double(number) else { return nil }
            switch character {
            case "H": total += value * 3600
            case "M": total += value * 60
            case "S": total += value
            default: return nil
            }
            number = ""
        }
        return number.isEmpty ? total : nil
    }

    public func accepts(width: Int, height: Int) -> Bool {
        sizes.contains { $0.fits(width: width, height: height) }
    }

    public var sizeList: String { ImageRules(sizes: sizes).sizeList }
}

// MARK: - The checks

extension Validator {
    /// The app previews of a version.
    func validatePreviews(_ content: VersionContent) -> [Problem] {
        validatePreviewFolder(content.previewFolder, root: previewsPath(content))
    }

    /// The previews of one folder of `<locale>/<device class>/` folders.
    func validatePreviewFolder(_ folder: PreviewFolder, root: String) -> [Problem] {
        var problems: [Problem] = []
        let listed = Dictionary(uniqueKeysWithValues: config.resolvedDeviceClasses.map { ($0.id, $0) })

        for slot in folder.previews.keys.sorted(by: { ($0.locale, $0.deviceClassID) < ($1.locale, $1.deviceClassID) }) {
            let files = folder.previews[slot] ?? []
            let path = "\(root)/\(slot.locale)/\(slot.deviceClassID)"
            guard let deviceClass = listed[slot.deviceClassID] else {
                if files.isEmpty == false {
                    problems.append(previewProblem(.warning, kind: .deviceClassNotKnown, slot: slot, path: path,
                                                   message: LocalizedStringResource(
                                                       "\(path) holds previews for a device class this project does not list.",
                                                       bundle: .here
                                                   ),
                                                   fix: LocalizedStringResource("Nothing uploads them.", bundle: .here)))
                }
                continue
            }
            problems += validatePreviewSlot(files, slot: slot, deviceClass: deviceClass, path: path,
                                            posterFrames: folder.posterFrames[slot] ?? [:],
                                            posterFramesUnreadable: folder.unreadablePosterFrames.contains(slot))
        }
        return problems
    }

    // swiftlint:disable:next function_parameter_count
    private func validatePreviewSlot(
        _ files: [PreviewFile],
        slot: ScreenshotSlot,
        deviceClass: DeviceClass,
        path: String,
        posterFrames: [String: String],
        posterFramesUnreadable: Bool
    ) -> [Problem] {
        var problems: [Problem] = []
        guard deviceClass.takesPreviews else {
            guard files.isEmpty == false else { return [] }
            return [previewProblem(.error, kind: .previewDeviceClassTakesNone, slot: slot, path: path,
                                   message: LocalizedStringResource(
                                       "App Store Connect takes no app preview for \(deviceClass.displayName).",
                                       bundle: .here
                                   ),
                                   fix: LocalizedStringResource("Remove the folder \(path).", bundle: .here))]
        }

        let rules = VideoRules.preview(of: deviceClass, refData: refData)
        if files.count > VideoRules.maximumPerSet {
            let limit = VideoRules.maximumPerSet
            let message = LocalizedStringResource("""
            \(path) has more previews than App Store Connect takes. The limit is \(limit).
            """, bundle: .here)
            problems.append(previewProblem(.error, kind: .previewsOverLimit, slot: slot, path: path,
                                           message: message, fix: nil))
        }
        if posterFramesUnreadable {
            problems.append(previewProblem(.error, kind: .previewPosterFramesUnreadable, slot: slot, path: path,
                                           message: LocalizedStringResource(
                                               "ASCKit cannot read \(path)/\(PosterFrames.fileName).", bundle: .here
                                           ),
                                           fix: LocalizedStringResource("""
                                           It has to map each file name to a time code, such as \
                                           {"01-a.mov": "00:00:05:00"}.
                                           """, bundle: .here)))
        }
        let names = Set(files.map(\.fileName))
        for name in posterFrames.keys.sorted() where names.contains(name) == false {
            problems.append(previewProblem(.warning, kind: .previewPosterFrameNamesNoFile, slot: slot, path: path,
                                           message: LocalizedStringResource(
                                               "\(PosterFrames.fileName) names \(name), and \(path) has no such file.",
                                               bundle: .here
                                           ),
                                           fix: LocalizedStringResource("Rename the entry or remove it.", bundle: .here)))
        }
        for file in files {
            problems += validatePreview(file, rules: rules, slot: slot, path: "\(path)/\(file.fileName)")
        }
        return problems
    }

    private func validatePreview(_ file: PreviewFile, rules: VideoRules, slot: ScreenshotSlot, path: String) -> [Problem] {
        var problems: [Problem] = []
        func add(_ severity: Problem.Severity, _ kind: Problem.Kind,
                 _ message: LocalizedStringResource, _ fix: LocalizedStringResource?) {
            problems.append(previewProblem(severity, kind: kind, slot: slot, path: path, message: message, fix: fix))
        }

        let ext = "." + file.url.pathExtension.lowercased()
        if rules.fileExtensions.contains(ext) == false {
            add(.error, .previewWrongFileType,
                LocalizedStringResource("App Store Connect does not take \(file.fileName) as an app preview.", bundle: .here),
                LocalizedStringResource("Export it as \(rules.fileExtensions.formatted(.list(type: .or, width: .narrow))).",
                                        bundle: .here))
            return problems
        }
        guard file.isReadable, let width = file.pixelWidth, let height = file.pixelHeight, let duration = file.duration
        else {
            add(.error, .previewUnreadable,
                LocalizedStringResource("\(file.fileName) could not be read as a movie.", bundle: .here),
                LocalizedStringResource("Everything in this folder is uploaded. Remove the file or replace it.",
                                        bundle: .here))
            return problems
        }

        if rules.accepts(width: width, height: height) == false {
            add(.error, .previewWrongSize,
                LocalizedStringResource("\(file.fileName) is \("\(width)x\(height)") pixels.", bundle: .here),
                LocalizedStringResource("App previews here are \(rules.sizeList), or the same pair swapped.", bundle: .here))
        }
        if rules.duration.contains(duration) == false {
            let length = Duration.seconds(duration).formatted(.units(allowed: [.seconds], fractionalPart: .show(length: 1)))
            let low = Duration.seconds(rules.duration.lowerBound).formatted(.units(allowed: [.seconds]))
            let high = Duration.seconds(rules.duration.upperBound).formatted(.units(allowed: [.seconds]))
            add(.error, .previewWrongLength,
                LocalizedStringResource("\(file.fileName) runs for \(length).", bundle: .here),
                LocalizedStringResource("An app preview runs from \(low) to \(high).", bundle: .here))
        }
        if let rate = file.frameRate, rules.frameRates.contains(rate.rounded()) == false {
            let shown = rate.formatted(.number.precision(.fractionLength(0 ... 2)))
            add(.error, .previewWrongFrameRate,
                LocalizedStringResource("\(file.fileName) has \(shown) frames a second.", bundle: .here),
                LocalizedStringResource("""
                App Store Connect takes \(Int(rules.frameRates.lowerBound)) to \(Int(rules.frameRates.upperBound)) \
                frames a second.
                """, bundle: .here))
        }
        if file.isFragmented {
            add(.warning, .previewFragmented,
                LocalizedStringResource("\(file.fileName) is a fragmented movie, so ASCKit cannot read its frame rate.",
                                        bundle: .here),
                LocalizedStringResource("Export it again as one movie.", bundle: .here))
        }
        if let codec = file.videoCodec, Self.acceptedCodecs(for: ext).contains(codec) == false {
            add(.error, .previewCodecNotAccepted,
                LocalizedStringResource("\(file.fileName) is encoded as \(codec).", bundle: .here),
                LocalizedStringResource("Export it as H.264, or as ProRes 422 HQ in a .mov file.", bundle: .here))
        }
        if file.byteCount > rules.maxFileSize {
            add(.error, .previewTooLarge,
                LocalizedStringResource("\(file.fileName) is \(Int64(file.byteCount).formatted(.byteCount(style: .file))).",
                                        bundle: .here),
                LocalizedStringResource("""
                App Store Connect takes a file of at most \(Int64(rules.maxFileSize).formatted(.byteCount(style: .file))).
                """, bundle: .here))
        }
        if rules.audioRequired, file.hasAudio == false {
            add(.warning, .previewHasNoAudio,
                LocalizedStringResource("\(file.fileName) has no sound track.", bundle: .here),
                LocalizedStringResource("App Store Connect wants one, even a silent one.", bundle: .here))
        }
        if let posterFrame = file.posterFrame {
            let seconds = PosterFrames.seconds(of: posterFrame, frameRate: file.frameRate ?? 30)
            if seconds == nil || seconds.map({ $0 > duration }) == true {
                add(.error, .previewPosterFrameNotValid,
                    LocalizedStringResource("The poster frame of \(file.fileName) is \(posterFrame).", bundle: .here),
                    LocalizedStringResource("""
                    Write it as hours, minutes, seconds and frames, such as 00:00:05:00, and keep it inside the video.
                    """, bundle: .here))
            }
        }
        return problems
    }

    /// H.264 in any of the three, and ProRes 422 HQ only in a QuickTime movie.
    static func acceptedCodecs(for ext: String) -> Set<String> {
        ext == ".mov" ? ["avc1", "avc3", "apch"] : ["avc1", "avc3"]
    }

    // swiftlint:disable:next function_parameter_count
    private func previewProblem(
        _ severity: Problem.Severity,
        kind: Problem.Kind,
        slot: ScreenshotSlot,
        path: String,
        message: LocalizedStringResource,
        fix: LocalizedStringResource?
    ) -> Problem {
        Problem(
            severity: severity,
            area: .screenshots,
            message: message,
            fix: fix,
            locale: slot.locale,
            deviceClassID: slot.deviceClassID,
            path: path,
            kind: kind
        )
    }
}

extension Validator {
    /// The previews of every treatment, one treatment folder at a time.
    func validateExperimentPreviews(_ experiments: ExperimentContent) -> [Problem] {
        let byTreatment = Dictionary(grouping: experiments.previews.keys) { "\($0.experiment)/\($0.treatment)" }
        return byTreatment.keys.sorted().flatMap { treatment in
            var folder = PreviewFolder()
            for slot in byTreatment[treatment] ?? [] {
                folder.previews[ScreenshotSlot(locale: slot.locale, deviceClassID: slot.deviceClassID)]
                    = experiments.previews(in: slot)
            }
            let root = "\(ExperimentFolders.folderName)/\(treatment)/\(ExperimentContentStore.previewsFolderName)"
            return validatePreviewFolder(folder, root: root)
        }
    }
}
