import Foundation
import ImageIO

/// One image on disk, with the facts App Store Connect cares about.
public struct ScreenshotFile: Sendable, Hashable, Identifiable {
    public let url: URL
    public let fileName: String
    public let byteCount: Int

    /// Nil when the file could not be read as an image at all, which is itself
    /// worth reporting.
    public let pixelWidth: Int?
    public let pixelHeight: Int?

    /// App Store Connect refuses an image with an alpha channel, and design
    /// tools write one even on fully opaque artwork.
    ///
    /// Nil only when the file could not be read as an image at all.
    public let hasAlpha: Bool?

    /// When the file was last written.
    ///
    /// This is what says which of two languages got the newer export. Nothing
    /// inside a PNG records that, and the order of the file names says nothing
    /// about it either.
    ///
    /// Nil when the file system did not answer.
    public let modifiedAt: Date?

    public var id: URL { url }

    public init(
        url: URL,
        fileName: String,
        byteCount: Int,
        pixelWidth: Int?,
        pixelHeight: Int?,
        hasAlpha: Bool?,
        modifiedAt: Date? = nil
    ) {
        self.url = url
        self.fileName = fileName
        self.byteCount = byteCount
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.hasAlpha = hasAlpha
        self.modifiedAt = modifiedAt
    }

    public var pixelDescription: String {
        guard let pixelWidth, let pixelHeight else {
            return String(localized: "unreadable", bundle: .module)
        }
        return "\(pixelWidth)x\(pixelHeight)"
    }
}

/// Reads the size and the alpha channel without decoding the whole image.
public enum ImageInspector {
    public static func inspect(url: URL) -> ScreenshotFile {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
        let byteCount = values?.fileSize ?? 0
        let modifiedAt = values?.contentModificationDate

        guard
            let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else {
            return ScreenshotFile(
                url: url,
                fileName: url.lastPathComponent,
                byteCount: byteCount,
                pixelWidth: nil,
                pixelHeight: nil,
                hasAlpha: nil,
                modifiedAt: modifiedAt
            )
        }

        // ImageIO leaves kCGImagePropertyHasAlpha out entirely for an image
        // with no alpha channel, rather than reporting false. Absent means no.
        return ScreenshotFile(
            url: url,
            fileName: url.lastPathComponent,
            byteCount: byteCount,
            pixelWidth: properties[kCGImagePropertyPixelWidth] as? Int,
            pixelHeight: properties[kCGImagePropertyPixelHeight] as? Int,
            hasAlpha: properties[kCGImagePropertyHasAlpha] as? Bool ?? false,
            modifiedAt: modifiedAt
        )
    }
}
