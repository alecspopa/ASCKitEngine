import ASCKitAPI
import Foundation

// MARK: - What a role accepts

/// The sizes, types and lengths App Store Connect takes for one role.
public struct CreativeRules: Sendable {
    public struct ImageRule: Sendable {
        public let size: AssetLibraryRefData.Dimensions
        /// Width and height, such as 3 and 2. Nil when any shape inside the
        /// range goes.
        public let ratio: (Int, Int)?
        public let fileExtensions: [String]
        public let alphaAllowed: Bool
        /// Fits both the header and search results.
        public let universal: Bool

        /// For an exact size the ratio Apple names is a rounded label:
        /// 3840x1646 is "21:9" and 5244x2950 is "16:9". It is a rule only
        /// for a range of sizes, such as search results at 3:2.
        func fits(width: Int, height: Int) -> Bool {
            guard size.fits(width: width, height: height) else { return false }
            let exact = size.minWidth == size.maxWidth && size.minHeight == size.maxHeight
            guard exact == false, let (wide, high) = ratio else { return true }
            return width * high == height * wide || height * high == width * wide
        }
    }

    public let images: [ImageRule]
    public let videoSizes: [ImageRule]
    public let duration: ClosedRange<Double>
    public let frameRates: [Double]

    public static func rules(for role: CreativeRole, refData: AssetLibraryRefData?) -> CreativeRules {
        let imageSpecs = refData?.imageSpecs(type: role.placementType, group: CreativeRole.group) ?? []
        guard imageSpecs.isEmpty == false else { return builtIn(role) }
        let videoSpecs = refData?.videoSpecs(type: role.placementType, group: CreativeRole.group) ?? []

        let images = imageSpecs.compactMap { spec -> ImageRule? in
            guard let size = spec.dimensions else { return nil }
            return ImageRule(size: size, ratio: spec.aspectRatio.flatMap(Self.ratio),
                             fileExtensions: (spec.fileExtensions ?? []).map { $0.lowercased() },
                             alphaAllowed: spec.alphaAllowed == true, universal: spec.universalAsset == true)
        }
        let videos = videoSpecs.compactMap { spec -> ImageRule? in
            guard let size = spec.dimensions else { return nil }
            return ImageRule(size: size, ratio: spec.aspectRatio.flatMap(Self.ratio),
                             fileExtensions: (spec.fileExtensions ?? []).map { $0.lowercased() },
                             alphaAllowed: false, universal: spec.universalAsset == true)
        }
        let rates = videoSpecs.flatMap { $0.frameRates ?? [] }.flatMap { [Double($0.minFps), Double($0.maxFps)] }
        let low = videoSpecs.compactMap { $0.duration?.min.flatMap(VideoRules.seconds) }.min() ?? 5
        let high = videoSpecs.compactMap { $0.duration?.max.flatMap(VideoRules.seconds) }.max() ?? 30
        return CreativeRules(images: images, videoSizes: videos.isEmpty ? builtIn(role).videoSizes : videos,
                             duration: low ... max(low, high),
                             frameRates: rates.isEmpty ? [30, 60] : Array(Set(rates)).sorted())
    }

    /// Apple's creative assets specification, for a check with no reference data.
    static func builtIn(_ role: CreativeRole) -> CreativeRules {
        let still = [".jpg", ".jpeg", ".png"]
        let movie = [".mov", ".m4v", ".mp4"]
        let wide = ImageRule(size: exact(5244, 2950), ratio: nil, fileExtensions: [".png"],
                             alphaAllowed: false, universal: true)
        switch role {
        case .header:
            return CreativeRules(
                images: [ImageRule(size: exact(3840, 1646), ratio: nil, fileExtensions: still,
                                   alphaAllowed: false, universal: false), wide],
                videoSizes: [ImageRule(size: exact(3840, 1646), ratio: nil, fileExtensions: movie,
                                       alphaAllowed: false, universal: false)],
                duration: 5 ... 30, frameRates: [30, 60]
            )
        case .searchResults:
            let range = AssetLibraryRefData.Dimensions(minWidth: 1920, maxWidth: 3840, minHeight: 1280, maxHeight: 2560)
            return CreativeRules(
                images: [ImageRule(size: range, ratio: (3, 2), fileExtensions: still,
                                   alphaAllowed: false, universal: false), wide],
                videoSizes: [ImageRule(size: range, ratio: (3, 2), fileExtensions: movie,
                                       alphaAllowed: false, universal: false)],
                duration: 5 ... 30, frameRates: [30, 60]
            )
        }
    }

    private static func exact(_ width: Int, _ height: Int) -> AssetLibraryRefData.Dimensions {
        .init(minWidth: width, maxWidth: width, minHeight: height, maxHeight: height)
    }

    /// `3:2` as (3, 2).
    static func ratio(_ text: String) -> (Int, Int)? {
        let parts = text.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2, parts[0] > 0, parts[1] > 0 else { return nil }
        return (parts[0], parts[1])
    }

    /// The rules this file meets for its size and kind, if any.
    func matching(_ file: CreativeFile) -> [ImageRule] {
        guard let width = file.pixelWidth, let height = file.pixelHeight else { return [] }
        let ext = "." + file.url.pathExtension.lowercased()
        let candidates = file.media == .video ? videoSizes : images
        return candidates.filter { $0.fits(width: width, height: height) && $0.fileExtensions.contains(ext) }
    }

    var sizeList: String {
        images.map { rule in
            let low = "\(rule.size.minWidth)x\(rule.size.minHeight)"
            let high = "\(rule.size.maxWidth)x\(rule.size.maxHeight)"
            return low == high ? low : "\(low) to \(high)"
        }
        .formatted(.list(type: .or, width: .narrow))
    }
}

// MARK: - The checks

extension Validator {
    func validateCreative(_ content: VersionContent) -> [Problem] {
        validateCreativeFolder(content.creativeFolder, root: "versions/\(content.versionString)/\(CreativeFolder.folderName)")
    }

    func validateExperimentCreative(_ experiments: ExperimentContent) -> [Problem] {
        experiments.creative.keys.sorted().flatMap { treatment in
            validateCreativeFolder(
                experiments.creative[treatment] ?? CreativeFolder(),
                root: "\(ExperimentFolders.folderName)/\(treatment)/\(CreativeFolder.folderName)"
            )
        }
    }

    func validateCreativeFolder(_ folder: CreativeFolder, root: String) -> [Problem] {
        var problems: [Problem] = []

        for locale in Set(folder.files.keys).union(folder.strays.keys).sorted() {
            let path = "\(root)/\(locale)"
            for stray in folder.strays[locale] ?? [] {
                problems.append(creativeProblem(.warning, .creativeFileNotKnown, locale: locale, path: "\(path)/\(stray)",
                                                LocalizedStringResource("ASCKit does not know what \(stray) is for.", bundle: .here),
                                                LocalizedStringResource("""
                                                Name it header or search-results, with its extension. Nothing uploads it.
                                                """, bundle: .here)))
            }
            for role in CreativeRole.allCases {
                let files = folder.files[locale]?[role] ?? []
                if files.count > 1 {
                    let names = files.map(\.fileName).formatted(.list(type: .and, width: .narrow))
                    problems.append(creativeProblem(.error, .creativeTwoFiles, locale: locale, path: path,
                                                    LocalizedStringResource("\(path) has \(names).", bundle: .here),
                                                    LocalizedStringResource("Keep one. App Store Connect shows one.",
                                                                            bundle: .here)))
                }
                guard let file = files.first else { continue }
                problems += validateCreativeFile(file, role: role, locale: locale, path: "\(path)/\(file.fileName)")
            }

            let header = folder.file(locale: locale, role: .header)
            let search = folder.file(locale: locale, role: .searchResults)
            // With no search results file, App Store Connect shows the header there.
            if let header, search == nil {
                let fitsSearch = CreativeRules.rules(for: .searchResults, refData: refData).matching(header).isEmpty == false
                let universal = CreativeRules.rules(for: .header, refData: refData).matching(header).contains(where: \.universal)
                if fitsSearch == false || universal == false {
                    problems.append(creativeProblem(.error, .creativeHeaderNotUniversal, locale: locale,
                                                    path: "\(path)/\(header.fileName)",
                                                    LocalizedStringResource("""
                                                    \(header.fileName) also goes into search results, \
                                                    because this language has no search results file. Only a \
                                                    universal image fits both.
                                                    """, bundle: .here),
                                                    LocalizedStringResource("""
                                                    Use a 5244x2950 png, or add a search-results file for this language.
                                                    """, bundle: .here)))
                }
            }
        }
        return problems
    }

    private func validateCreativeFile(_ file: CreativeFile, role: CreativeRole, locale: String, path: String) -> [Problem] {
        var problems: [Problem] = []
        let ext = file.url.pathExtension.lowercased()
        guard CreativeFolder.imageExtensions.contains(ext) || CreativeFolder.videoExtensions.contains(ext) else {
            return [creativeProblem(.error, .creativeWrongFileType, locale: locale, path: path,
                                    LocalizedStringResource("App Store Connect does not take \(file.fileName).",
                                                            bundle: .here),
                                    LocalizedStringResource("Export it as png, jpg, mov, mp4 or m4v.", bundle: .here))]
        }
        guard let width = file.pixelWidth, let height = file.pixelHeight else {
            return [creativeProblem(.error, .creativeUnreadable, locale: locale, path: path,
                                    LocalizedStringResource("\(file.fileName) could not be read.", bundle: .here), nil)]
        }

        let rules = CreativeRules.rules(for: role, refData: refData)
        let matches = rules.matching(file)
        if matches.isEmpty {
            problems.append(creativeProblem(.error, .creativeWrongSize, locale: locale, path: path,
                                            LocalizedStringResource("\(file.fileName) is \("\(width)x\(height)") pixels.",
                                                                    bundle: .here),
                                            LocalizedStringResource("""
                                            Here App Store Connect takes \(rules.sizeList), in the file types each \
                                            size allows.
                                            """, bundle: .here)))
        }
        if file.media == .image, file.hasAlpha == true, matches.allSatisfy({ $0.alphaAllowed == false }) {
            problems.append(creativeProblem(.error, .creativeHasAlpha, locale: locale, path: path,
                                            LocalizedStringResource("\(file.fileName) has an alpha channel.",
                                                                    bundle: .here),
                                            LocalizedStringResource("Export it again without one.", bundle: .here)))
        }
        if file.media == .video {
            if let duration = file.duration, rules.duration.contains(duration) == false {
                let length = Duration.seconds(duration).formatted(.units(allowed: [.seconds], fractionalPart: .show(length: 1)))
                problems.append(creativeProblem(.error, .creativeWrongLength, locale: locale, path: path,
                                                LocalizedStringResource("\(file.fileName) runs for \(length).",
                                                                        bundle: .here),
                                                LocalizedStringResource("A header or search results video runs 5 to 30 seconds.",
                                                                        bundle: .here)))
            }
            if let rate = file.frameRate, rules.frameRates.contains(rate.rounded()) == false {
                let shown = rate.formatted(.number.precision(.fractionLength(0 ... 2)))
                problems.append(creativeProblem(.error, .creativeWrongFrameRate, locale: locale, path: path,
                                                LocalizedStringResource("\(file.fileName) has \(shown) frames a second.",
                                                                        bundle: .here),
                                                LocalizedStringResource("Export it at 30 or 60 frames a second.",
                                                                        bundle: .here)))
            }
        }
        return problems
    }

    // swiftlint:disable:next function_parameter_count
    private func creativeProblem(
        _ severity: Problem.Severity,
        _ kind: Problem.Kind,
        locale: String,
        path: String,
        _ message: LocalizedStringResource,
        _ fix: LocalizedStringResource?
    ) -> Problem {
        Problem(severity: severity, area: .screenshots, message: message, fix: fix, locale: locale, path: path, kind: kind)
    }
}
