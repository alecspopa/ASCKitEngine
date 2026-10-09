import ASCKitAPI
import Foundation

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

    // MARK: Apple's published numbers

    static let iPadSize = (width: 1200, height: 1600)
    static let desktopSize = (width: 1920, height: 1080)
    static let visionProSize = (width: 3840, height: 2160)
    static let phoneSize = (width: 886, height: 1920)
    static let defaultFrameRates: ClosedRange<Double> = 1 ... 30
    static let defaultDuration: ClosedRange<Double> = 15 ... 30
    static let defaultMaxFileSize = 500 * 1024 * 1024

    public static func preview(of deviceClass: DeviceClass, refData: AssetLibraryRefData?) -> VideoRules {
        let specs = refData?.videoSpecs(type: .appPreview, group: deviceClass.placementGroup) ?? []
        guard specs.isEmpty == false else { return builtIn(deviceClass) }

        let rates = specs.flatMap { $0.frameRates ?? [] }
        let low = specs.compactMap { $0.duration?.min.flatMap(Self.seconds) }.min() ?? Self.defaultDuration.lowerBound
        let high = specs.compactMap { $0.duration?.max.flatMap(Self.seconds) }.max() ?? Self.defaultDuration.upperBound
        return VideoRules(
            sizes: specs.compactMap(\.dimensions),
            frameRates: (rates.map { Double($0.minFps) }.min() ?? Self.defaultFrameRates.lowerBound)
                ... (rates.map { Double($0.maxFps) }.max() ?? Self.defaultFrameRates.upperBound),
            duration: low ... max(low, high),
            audioRequired: specs.contains { $0.audioRequired == true },
            maxFileSize: specs.compactMap(\.maxFileSize).max() ?? Self.defaultMaxFileSize,
            fileExtensions: Array(Set(specs.flatMap { $0.fileExtensions ?? [] }.map { $0.lowercased() })).sorted()
        )
    }

    /// Apple's app preview specification, for a check with no reference data.
    static func builtIn(_ deviceClass: DeviceClass) -> VideoRules {
        let size = switch deviceClass.family {
        case "iPad": iPadSize
        case "Mac", "Apple TV": desktopSize
        case "Apple Vision Pro": visionProSize
        default: phoneSize
        }
        return VideoRules(
            sizes: [.init(minWidth: size.width, maxWidth: size.width, minHeight: size.height, maxHeight: size.height)],
            frameRates: defaultFrameRates,
            duration: defaultDuration,
            audioRequired: false,
            maxFileSize: defaultMaxFileSize,
            fileExtensions: MediaExtensions.dotted(MediaExtensions.video)
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
