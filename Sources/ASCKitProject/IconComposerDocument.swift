import CoreGraphics
import Foundation

/// An Icon Composer document, read into the pieces a drawing needs.
///
/// A `.icon` file holds the layers an icon is built from rather than a picture
/// of one. `icon.json` says what the layers are, what fills them and where they
/// sit, and the artwork itself is in `Assets` beside it.
///
/// Reading is here, beside the rest of what the package knows about a project.
/// Drawing is in the app, because it needs a graphics context and the command
/// line tool has no window.
public struct IconComposerDocument: Sendable {
    /// What fills the square behind every layer.
    public let background: Fill?

    /// Bottom first, so a caller draws them in the order it gets them. The file
    /// keeps them the other way round, topmost first, which is the order the
    /// layer list in Icon Composer shows.
    public let groups: [Group]

    /// A set of layers that Icon Composer moves and lights as one.
    public struct Group: Sendable {
        /// Bottom first, for the same reason the groups are.
        public let layers: [Layer]
        public let placement: Placement
    }

    /// One piece of artwork, and what to do with it.
    public struct Layer: Sendable {
        /// The file in `Assets`. It is usually an SVG, drawn at 1024 points
        /// square, which is the size of the icon canvas.
        public let imageURL: URL

        /// The colour the artwork is painted in. The artwork carries its own
        /// colours when this is nil, and is a shape to fill when it is not.
        public let fill: Fill?

        public let opacity: Double
        public let placement: Placement
    }

    /// Where a layer or a group sits, against the middle of the canvas.
    public struct Placement: Sendable {
        public let scale: Double

        /// Points on the 1024 canvas, x to the right and y down.
        public let offset: CGPoint

        public static let unmoved = Placement(scale: 1, offset: .zero)
    }

    /// A colour, or a gradient between colours.
    public enum Fill: Sendable {
        case solid(Colour)

        /// `start` and `stop` are fractions of the canvas, x to the right and
        /// y down, so `(0.5, 0)` is the top middle.
        case gradient(colours: [Colour], start: CGPoint, stop: CGPoint)
    }

    /// A colour as the file writes it, which is a colour space and four
    /// components rather than one of AppKit's.
    public struct Colour: Sendable, Hashable {
        public let red: Double
        public let green: Double
        public let blue: Double
        public let alpha: Double
        public let space: Space

        public enum Space: String, Sendable {
            case displayP3 = "display-p3"
            case sRGB = "srgb"
            case extendedSRGB = "extended-srgb"
            case extendedGray = "extended-gray"

            /// A grey space writes one component where a colour space writes
            /// three, and an alpha after it either way.
            var isGrey: Bool { self == .extendedGray }
        }

        /// The same colour mixed towards white, which is how the gradient
        /// Icon Composer works out for itself is approximated.
        public func lightened(by amount: Double) -> Colour {
            Colour(
                red: red + (1 - red) * amount,
                green: green + (1 - green) * amount,
                blue: blue + (1 - blue) * amount,
                alpha: alpha,
                space: space
            )
        }

        /// `display-p3:0.35952,0.38713,0.90842,1.00000`, which is the shape the
        /// file writes a colour in. A grey space writes two numbers rather than
        /// four: `extended-gray:0.50000,1.00000`.
        static func read(_ text: String) -> Colour? {
            let halves = text.split(separator: ":", maxSplits: 1)
            guard halves.count == 2 else { return nil }

            // A space this does not know is read as sRGB. The numbers are still
            // a colour, and one drawn a shade out beats an icon that is gone.
            let space = Space(rawValue: String(halves[0])) ?? .sRGB
            let parts = halves[1].split(separator: ",").compactMap { Double($0) }

            if space.isGrey {
                guard let white = parts.first else { return nil }
                return Colour(
                    red: white,
                    green: white,
                    blue: white,
                    alpha: parts.count > 1 ? parts[1] : 1,
                    space: space
                )
            }

            guard parts.count >= 3 else { return nil }

            return Colour(
                red: parts[0],
                green: parts[1],
                blue: parts[2],
                alpha: parts.count > 3 ? parts[3] : 1,
                space: space
            )
        }
    }

    /// What a folder that is not an Icon Composer document, or one this cannot
    /// make sense of, answers with.
    public enum Failure: Error, CustomLocalizedStringResourceConvertible {
        case noDocument(at: URL)

        public var localizedStringResource: LocalizedStringResource {
            switch self {
            case let .noDocument(folder):
                LocalizedStringResource("There is no icon.json in \(folder.path).", bundle: .here)
            }
        }
    }

    /// Reads the document in a `.icon` folder.
    public static func read(at folderURL: URL) throws -> IconComposerDocument {
        let jsonURL = folderURL.appending(path: "icon.json")
        guard let data = try? Data(contentsOf: jsonURL) else { throw Failure.noDocument(at: folderURL) }

        let file = try JSONDecoder().decode(File.self, from: data)
        let assets = folderURL.appending(path: "Assets")

        return IconComposerDocument(
            background: file.background,
            groups: file.groups.reversed().map { group in
                Group(
                    layers: group.layers.reversed().compactMap { $0.layer(in: assets) },
                    placement: group.position?.placement ?? .unmoved
                )
            }
        )
    }
}

// MARK: - The file

/// The shapes `icon.json` is written in, which are not the shapes a drawing
/// wants. Everything here is read once and turned into the types above.
private extension IconComposerDocument {
    struct File: Decodable {
        let fill: FillValue?
        let fillSpecializations: [Specialization]?
        let groups: [GroupValue]

        enum CodingKeys: String, CodingKey {
            case fill
            case fillSpecializations = "fill-specializations"
            case groups
        }

        /// A document says its background either once or once per appearance.
        /// The one with no appearance on it is the light one, which is the one
        /// drawn here.
        var background: Fill? {
            fill?.read ?? fillSpecializations?.light?.read
        }
    }

    struct Specialization: Decodable {
        let appearance: String?
        let value: FillValue
    }

    struct GroupValue: Decodable {
        let layers: [LayerValue]
        let position: PositionValue?
    }

    struct LayerValue: Decodable {
        let imageName: String
        let fill: FillValue?
        let fillSpecializations: [Specialization]?
        let opacity: Double?
        let position: PositionValue?

        enum CodingKeys: String, CodingKey {
            case imageName = "image-name"
            case fill
            case fillSpecializations = "fill-specializations"
            case opacity
            case position
        }

        func layer(in assets: URL) -> Layer? {
            guard imageName.isEmpty == false else { return nil }
            return Layer(
                imageURL: assets.appending(path: imageName),
                fill: fill?.read ?? fillSpecializations?.light?.read,
                opacity: opacity ?? 1,
                placement: position?.placement ?? .unmoved
            )
        }
    }

    struct PositionValue: Decodable {
        let scale: Double?
        let translationInPoints: [Double]?

        enum CodingKeys: String, CodingKey {
            case scale
            case translationInPoints = "translation-in-points"
        }

        var placement: Placement {
            let offset = translationInPoints ?? []
            return Placement(
                scale: scale ?? 1,
                offset: CGPoint(x: offset.first ?? 0, y: offset.count > 1 ? offset[1] : 0)
            )
        }
    }

    struct FillValue: Decodable {
        let solid: String?
        let linearGradient: [String]?
        let automaticGradient: String?
        let orientation: Orientation?

        enum CodingKeys: String, CodingKey {
            case solid
            case linearGradient = "linear-gradient"
            case automaticGradient = "automatic-gradient"
            case orientation
        }

        /// A layer that keeps its own colours writes the word `automatic` where
        /// every other layer writes an object. Read as a fill that says nothing,
        /// so the artwork is drawn as it is.
        ///
        /// Written by hand because one word and one object in the same place
        /// is more than a synthesised decoder will take, and a document holding
        /// such a layer used to fail to read as a whole.
        init(from decoder: any Decoder) throws {
            if let single = try? decoder.singleValueContainer(), (try? single.decode(String.self)) != nil {
                solid = nil
                linearGradient = nil
                automaticGradient = nil
                orientation = nil
                return
            }

            let values = try decoder.container(keyedBy: CodingKeys.self)
            solid = try values.decodeIfPresent(String.self, forKey: .solid)
            linearGradient = try values.decodeIfPresent([String].self, forKey: .linearGradient)
            automaticGradient = try values.decodeIfPresent(String.self, forKey: .automaticGradient)
            orientation = try values.decodeIfPresent(Orientation.self, forKey: .orientation)
        }

        /// How much lighter the top of an automatic gradient is than the
        /// colour it was worked out from. Measured off icons Xcode built,
        /// because Icon Composer does not write the two ends down.
        static let automaticLift = 0.25

        var read: Fill? {
            if let solid, let colour = Colour.read(solid) { return .solid(colour) }

            let start = orientation?.start.point ?? CGPoint(x: 0.5, y: 0)
            let stop = orientation?.stop.point ?? CGPoint(x: 0.5, y: 1)

            if let linearGradient {
                let colours = linearGradient.compactMap(Colour.read)
                return colours.isEmpty ? nil : .gradient(colours: colours, start: start, stop: stop)
            }

            if let automaticGradient, let colour = Colour.read(automaticGradient) {
                let lifted = colour.lightened(by: Self.automaticLift)
                return .gradient(colours: [lifted, colour], start: start, stop: stop)
            }

            return nil
        }
    }

    struct Orientation: Decodable {
        let start: Coordinate
        let stop: Coordinate

        struct Coordinate: Decodable {
            let x: Double
            let y: Double

            var point: CGPoint { CGPoint(x: x, y: y) }
        }
    }
}

private extension [IconComposerDocument.Specialization] {
    /// The one with no appearance named on it.
    var light: IconComposerDocument.FillValue? {
        (first { $0.appearance == nil } ?? first)?.value
    }
}

extension IconComposerDocument.Failure: CustomStringConvertible {
    public var description: String { String(localized: localizedStringResource) }
}
