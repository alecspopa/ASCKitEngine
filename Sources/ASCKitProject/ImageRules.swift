import ASCKitAPI
import Foundation

/// The image rules of one group, from the reference data when there is some
/// and from the built-in table when there is none.
public struct ImageRules: Sendable, Equatable {
    public let sizes: [AssetLibraryRefData.Dimensions]
    public let alphaAllowed: Bool
    public let maxFileSize: Int?

    /// Lower case, with the dot, such as `.png`. Empty means any.
    public let fileExtensions: [String]

    public init(
        sizes: [AssetLibraryRefData.Dimensions],
        alphaAllowed: Bool = false,
        maxFileSize: Int? = nil,
        fileExtensions: [String] = []
    ) {
        self.sizes = sizes
        self.alphaAllowed = alphaAllowed
        self.maxFileSize = maxFileSize
        self.fileExtensions = fileExtensions
    }

    public static func screenshot(of deviceClass: DeviceClass, refData: AssetLibraryRefData?) -> ImageRules {
        let specs = refData?.imageSpecs(type: deviceClass.screenshotPlacementType, group: deviceClass.placementGroup) ?? []
        guard specs.isEmpty == false else { return builtIn(deviceClass) }

        return ImageRules(
            sizes: specs.compactMap(\.dimensions),
            alphaAllowed: specs.contains { $0.alphaAllowed == true },
            maxFileSize: specs.compactMap(\.maxFileSize).max(),
            fileExtensions: Array(Set(specs.flatMap { $0.fileExtensions ?? [] }.map { $0.lowercased() })).sorted()
        )
    }

    static func builtIn(_ deviceClass: DeviceClass) -> ImageRules {
        ImageRules(sizes: deviceClass.acceptedSizes.map {
            AssetLibraryRefData.Dimensions(
                minWidth: $0.width, maxWidth: $0.width, minHeight: $0.height, maxHeight: $0.height
            )
        })
    }

    public func accepts(width: Int, height: Int) -> Bool {
        sizes.contains { $0.fits(width: width, height: height) }
    }

    public func accepts(fileName: String) -> Bool {
        guard fileExtensions.isEmpty == false else { return true }
        let ext = "." + (fileName.split(separator: ".").last.map { $0.lowercased() } ?? "")
        return fileExtensions.contains(ext)
    }

    /// Such as `1290x2796 and 1320x2868`. A range reads as `1920x1280 to 3840x2560`.
    public var sizeList: String {
        sizes.map { size in
            let low = "\(size.minWidth)x\(size.minHeight)"
            let high = "\(size.maxWidth)x\(size.maxHeight)"
            return low == high ? low : "\(low) to \(high)"
        }
        .formatted(.list(type: .and, width: .narrow))
    }
}
