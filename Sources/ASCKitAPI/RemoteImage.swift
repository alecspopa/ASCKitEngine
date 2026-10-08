import Foundation

/// An image App Store Connect serves, and the size it holds it at.
///
/// The address is a template. It names a width, a height and a file format,
/// and the image comes back fitted inside that box. A box of the shape of the
/// image itself keeps the shape, so a caller that knows only the height it has
/// room for asks for `url(pixelHeight:)`.
///
/// What comes back is a new encoding of the image somebody uploaded. It has
/// another checksum, so it is something to look at and never something to
/// write into a project.
public struct RemoteImage: Sendable, Equatable {
    public let template: String
    public let width: Int?
    public let height: Int?

    public init(template: String, width: Int?, height: Int?) {
        self.template = template
        self.width = width
        self.height = height
    }

    /// The image inside a box of this many pixels tall, as wide as the shape of
    /// the image makes it.
    public func url(pixelHeight: Int) -> URL? {
        guard pixelHeight > 0 else { return nil }
        guard let width, let height, width > 0, height > 0 else {
            return url(pixelWidth: pixelHeight, pixelHeight: pixelHeight)
        }

        let box = Double(pixelHeight) * Double(width) / Double(height)
        return url(pixelWidth: Int(box.rounded()), pixelHeight: pixelHeight)
    }

    public func url(pixelWidth: Int, pixelHeight: Int) -> URL? {
        let address = template
            .replacingOccurrences(of: "{w}", with: String(pixelWidth))
            .replacingOccurrences(of: "{h}", with: String(pixelHeight))
            // How the image is fitted into the box. Most templates name it
            // already and hold no `{c}` at all. `bb` is the one that keeps the
            // whole image, which is the point of showing it.
            .replacingOccurrences(of: "{c}", with: "bb")
            .replacingOccurrences(of: "{f}", with: "png")
        return URL(string: address)
    }
}
