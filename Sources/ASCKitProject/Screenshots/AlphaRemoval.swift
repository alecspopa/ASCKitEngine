import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Writing a waiting screenshot again with no alpha channel.
///
/// App Store Connect refuses an image that has one, and most design tools write
/// one into artwork that is fully opaque. That refusal is right: the file is
/// not what the store takes. It is also the one refusal where nothing about the
/// picture is wrong, so exporting it again is work that changes no pixel a
/// person can see.
///
/// So the refusal carries the fact that the channel is the only thing wrong,
/// and this writes the image again without it. The inbox sheet and
/// `asckit inbox --clear-alpha` both come here, so a file cleared from the
/// window and one cleared from the terminal end up the same.
///
/// The image is painted onto white first. A screenshot that really is part
/// transparent has to land on some colour once the channel goes, and white is
/// what the store shows behind a listing.
public enum AlphaRemoval {
    /// The waiting images that an alpha channel alone keeps out.
    ///
    /// Reads no files, so a view can ask on every redraw and a button can carry
    /// the count of what it would clear.
    public static func clearable(in plan: Inbox.Plan) -> [ScreenshotFile] {
        plan.refusals.filter(\.hasClearableAlpha).map(\.file)
    }

    // MARK: - Writing it

    /// One file nothing could be done about, and why.
    public struct Failure: Sendable, Equatable {
        public let fileName: String
        public let reason: String

        public init(fileName: String, reason: String) {
            self.fileName = fileName
            self.reason = reason
        }
    }

    /// What the clearing did.
    public struct Outcome: Sendable, Equatable {
        /// The files written again with no alpha channel, by name.
        public var cleared: [String] = []

        /// The files that still have one, and the reason each kept it.
        public var failed: [Failure] = []

        /// Where the file as it arrived went, so a caller can point at it
        /// rather than claiming it is gone.
        public var trashed: [URL] = []

        public init(cleared: [String] = [], failed: [Failure] = [], trashed: [URL] = []) {
            self.cleared = cleared
            self.failed = failed
            self.trashed = trashed
        }
    }

    /// Writes each of these images again with no alpha channel, over the file
    /// itself.
    ///
    /// The file as it arrived goes to the Trash first, for the reason the inbox
    /// trashes rather than deletes: the image somebody dropped in may be the
    /// only copy of that artwork anybody has, and this one changes its pixels.
    ///
    /// One file at a time. A file that cannot be read is reported and the rest
    /// are still cleared, because a batch that stopped on the first bad file
    /// would leave a person clearing them one by one.
    @discardableResult
    public static func clear(_ urls: [URL]) -> Outcome {
        var outcome = Outcome()

        for url in urls {
            do {
                let trashed = try clearOne(at: url)
                outcome.cleared.append(url.lastPathComponent)
                if let trashed { outcome.trashed.append(trashed) }
            } catch {
                outcome.failed.append(Failure(
                    fileName: url.lastPathComponent,
                    reason: "\(error)"
                ))
            }
        }
        return outcome
    }

    /// The whole image is made in memory before anything on disk moves, so a
    /// file that cannot be drawn is a file still sitting where it was.
    private static func clearOne(at url: URL) throws -> URL? {
        guard
            let source = CGImageSourceCreateWithURL(url as CFURL, nil),
            let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
        else {
            throw AlphaRemovalError.couldNotRead(url.lastPathComponent)
        }

        let flattened = try flatten(image, fileName: url.lastPathComponent)
        let type = CGImageSourceGetType(source) ?? UTType.png.identifier as CFString
        let data = try encode(flattened, as: type, fileName: url.lastPathComponent)

        var landed: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &landed)
        try data.write(to: url)
        return landed as URL?
    }

    /// The same picture on a white ground, in a bitmap that holds no alpha
    /// channel at all.
    private static func flatten(_ image: CGImage, fileName: String) throws -> CGImage {
        let width = image.width
        let height = image.height

        guard
            let space = drawingSpace(of: image),
            let context = CGContext(
                data: nil,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: space,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            )
        else {
            throw AlphaRemovalError.couldNotDraw(fileName)
        }

        let bounds = CGRect(x: 0, y: 0, width: width, height: height)
        context.setFillColor(gray: 1, alpha: 1)
        context.fill(bounds)
        context.draw(image, in: bounds)

        guard let flattened = context.makeImage() else {
            throw AlphaRemovalError.couldNotDraw(fileName)
        }
        return flattened
    }

    /// The image's own colour space, where a context can use it.
    ///
    /// Display P3 is what a recent iPhone screenshots in, and drawing it into
    /// sRGB would move every colour in the picture. Keeping the space means the
    /// only thing this changes is the channel it set out to remove. Anything
    /// that is not three channels of colour, such as greyscale or an indexed
    /// palette, gets sRGB.
    private static func drawingSpace(of image: CGImage) -> CGColorSpace? {
        if let space = image.colorSpace, space.model == .rgb, space.numberOfComponents == 3 {
            return space
        }
        return CGColorSpace(name: CGColorSpace.sRGB)
    }

    private static func encode(_ image: CGImage, as type: CFString, fileName: String) throws -> Data {
        let data = NSMutableData()
        guard
            let destination = CGImageDestinationCreateWithData(data, type, 1, nil)
        else {
            throw AlphaRemovalError.couldNotWrite(fileName)
        }

        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw AlphaRemovalError.couldNotWrite(fileName)
        }
        return data as Data
    }
}

public enum AlphaRemovalError: Error, CustomLocalizedStringResourceConvertible {
    case couldNotRead(String)
    case couldNotDraw(String)
    case couldNotWrite(String)

    public var localizedStringResource: LocalizedStringResource {
        switch self {
        case let .couldNotRead(fileName):
            LocalizedStringResource("\(fileName) could not be read as an image.", bundle: .here)
        case let .couldNotDraw(fileName):
            LocalizedStringResource("""
            \(fileName) could not be drawn again without its alpha channel.
            """, bundle: .here)
        case let .couldNotWrite(fileName):
            LocalizedStringResource("""
            \(fileName) could not be written again without its alpha channel.
            """, bundle: .here)
        }
    }
}

extension AlphaRemovalError: CustomStringConvertible {
    public var description: String { String(localized: localizedStringResource) }
}
