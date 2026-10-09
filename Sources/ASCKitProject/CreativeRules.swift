import ASCKitAPI
import Foundation

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

    // MARK: Apple's published numbers

    static let headerSize = exact(3840, 1646)
    static let wideSize = exact(5244, 2950)
    static let searchResultsSize = AssetLibraryRefData.Dimensions(
        minWidth: 1920, maxWidth: 3840, minHeight: 1280, maxHeight: 2560
    )
    static let searchResultsRatio = (3, 2)
    static let defaultDuration: ClosedRange<Double> = 5 ... 30
    static let defaultFrameRates: [Double] = [30, 60]

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
        let low = videoSpecs.compactMap { $0.duration?.min.flatMap(VideoRules.seconds) }.min() ?? Self.defaultDuration.lowerBound
        let high = videoSpecs.compactMap { $0.duration?.max.flatMap(VideoRules.seconds) }.max() ?? Self.defaultDuration.upperBound
        return CreativeRules(images: images, videoSizes: videos.isEmpty ? builtIn(role).videoSizes : videos,
                             duration: low ... max(low, high),
                             frameRates: rates.isEmpty ? Self.defaultFrameRates : Array(Set(rates)).sorted())
    }

    /// Apple's creative assets specification, for a check with no reference data.
    static func builtIn(_ role: CreativeRole) -> CreativeRules {
        let still = MediaExtensions.dotted(MediaExtensions.image)
        let movie = MediaExtensions.dotted(MediaExtensions.video)
        let wide = ImageRule(size: wideSize, ratio: nil, fileExtensions: [".png"],
                             alphaAllowed: false, universal: true)
        switch role {
        case .header:
            return CreativeRules(
                images: [ImageRule(size: headerSize, ratio: nil, fileExtensions: still,
                                   alphaAllowed: false, universal: false), wide],
                videoSizes: [ImageRule(size: headerSize, ratio: nil, fileExtensions: movie,
                                       alphaAllowed: false, universal: false)],
                duration: defaultDuration, frameRates: defaultFrameRates
            )
        case .searchResults:
            let range = searchResultsSize
            return CreativeRules(
                images: [ImageRule(size: range, ratio: searchResultsRatio, fileExtensions: still,
                                   alphaAllowed: false, universal: false), wide],
                videoSizes: [ImageRule(size: range, ratio: searchResultsRatio, fileExtensions: movie,
                                       alphaAllowed: false, universal: false)],
                duration: defaultDuration, frameRates: defaultFrameRates
            )
        }
    }

    static func exact(_ width: Int, _ height: Int) -> AssetLibraryRefData.Dimensions {
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
