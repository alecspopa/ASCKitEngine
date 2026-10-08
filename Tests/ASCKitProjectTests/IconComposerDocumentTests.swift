import CoreGraphics
import Foundation
import Testing
@testable import ASCKitProject

/// Reading a `.icon` folder into the pieces a drawing needs.
final class IconComposerDocumentTests {
    let fixture: FixtureProject

    init() throws {
        fixture = try FixtureProject()
    }

    deinit {
        fixture.remove()
    }

    /// Writes a document holding whatever JSON is given, with an `Assets`
    /// folder beside it.
    @discardableResult
    func write(_ json: String, named name: String = "AppIcon") throws -> URL {
        let folder = fixture.rootURL.appending(path: "\(name).icon")
        try FileManager.default.createDirectory(
            at: folder.appending(path: "Assets"),
            withIntermediateDirectories: true
        )
        try Data(json.utf8).write(to: folder.appending(path: "icon.json"))
        return folder
    }

    @Test
    func refusesAFolderWithNoDocumentInIt() throws {
        let folder = fixture.rootURL.appending(path: "Empty.icon")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        #expect(throws: IconComposerDocument.Failure.self) {
            try IconComposerDocument.read(at: folder)
        }
    }

    @Test
    func readsADocumentWithNothingInIt() throws {
        let folder = try write(#"{"groups":[]}"#)
        let document = try IconComposerDocument.read(at: folder)

        #expect(document.background == nil)
        #expect(document.groups.isEmpty)
    }

    // MARK: - The order

    /// The file lists the topmost group first, which is the order Icon Composer
    /// shows. A drawing needs the other one.
    @Test
    func handsBackTheBottomGroupFirst() throws {
        let folder = try write("""
        {"groups":[
          {"layers":[{"image-name":"top.svg","name":"top"}]},
          {"layers":[{"image-name":"bottom.svg","name":"bottom"}]}
        ]}
        """)

        let document = try IconComposerDocument.read(at: folder)
        let names = document.groups.flatMap(\.layers).map(\.imageURL.lastPathComponent)
        #expect(names == ["bottom.svg", "top.svg"])
    }

    /// Layers inside one group are listed the same way round as the groups.
    @Test
    func handsBackTheBottomLayerOfAGroupFirst() throws {
        let folder = try write("""
        {"groups":[{"layers":[
          {"image-name":"over.svg","name":"over"},
          {"image-name":"under.svg","name":"under"}
        ]}]}
        """)

        let document = try IconComposerDocument.read(at: folder)
        let names = document.groups[0].layers.map(\.imageURL.lastPathComponent)
        #expect(names == ["under.svg", "over.svg"])
    }

    @Test
    func putsTheArtworkInTheAssetsFolder() throws {
        let folder = try write(#"{"groups":[{"layers":[{"image-name":"page.svg","name":"page"}]}]}"#)
        let document = try IconComposerDocument.read(at: folder)

        #expect(document.groups[0].layers[0].imageURL == folder.appending(path: "Assets").appending(path: "page.svg"))
    }

    // MARK: - Fills

    @Test
    func readsASolidFill() throws {
        let folder = try write("""
        {"groups":[{"layers":[
          {"image-name":"page.svg","name":"page","fill":{"solid":"display-p3:1.00000,0.50000,0.25000,1.00000"}}
        ]}]}
        """)

        let document = try IconComposerDocument.read(at: folder)
        guard case let .solid(colour) = document.groups[0].layers[0].fill else {
            Issue.record("Expected a solid fill.")
            return
        }

        #expect(colour.red == 1)
        #expect(colour.green == 0.5)
        #expect(colour.blue == 0.25)
        #expect(colour.alpha == 1)
        #expect(colour.space == .displayP3)
    }

    @Test
    func readsTheBackgroundGradientAndWhereItRuns() throws {
        let folder = try write("""
        {"fill-specializations":[{"value":{
          "linear-gradient":["srgb:1.00000,1.00000,1.00000,1.00000","srgb:0.00000,0.00000,0.00000,1.00000"],
          "orientation":{"start":{"x":0.5,"y":0},"stop":{"x":0.5,"y":0.7}}
        }}],"groups":[]}
        """)

        let document = try IconComposerDocument.read(at: folder)
        guard case let .gradient(colours, start, stop) = document.background else {
            Issue.record("Expected a gradient background.")
            return
        }

        #expect(colours.count == 2)
        #expect(colours[0].space == .sRGB)
        #expect(start == CGPoint(x: 0.5, y: 0))
        #expect(stop == CGPoint(x: 0.5, y: 0.7))
    }

    /// A document can say its background once per appearance. The one with no
    /// appearance named on it is the light one.
    @Test
    func takesTheFillWithNoAppearanceOnIt() throws {
        let folder = try write("""
        {"fill-specializations":[
          {"appearance":"dark","value":{"solid":"srgb:0.00000,0.00000,0.00000,1.00000"}},
          {"value":{"solid":"srgb:1.00000,1.00000,1.00000,1.00000"}}
        ],"groups":[]}
        """)

        let document = try IconComposerDocument.read(at: folder)
        guard case let .solid(colour) = document.background else {
            Issue.record("Expected a solid background.")
            return
        }
        #expect(colour.red == 1)
    }

    /// Icon Composer works a gradient out from one colour and writes neither
    /// end down. The colour itself is the bottom end, and the top is lighter.
    @Test
    func liftsTheTopOfAnAutomaticGradient() throws {
        let folder = try write("""
        {"fill":{"automatic-gradient":"srgb:0.00000,0.40000,0.80000,1.00000",
          "orientation":{"start":{"x":0.5,"y":0},"stop":{"x":0.5,"y":1}}},"groups":[]}
        """)

        let document = try IconComposerDocument.read(at: folder)
        guard case let .gradient(colours, _, _) = document.background, colours.count == 2 else {
            Issue.record("Expected a gradient of two colours.")
            return
        }

        #expect(colours[0].red > colours[1].red)
        #expect(colours[0].blue > colours[1].blue)
        #expect(colours[1].blue == 0.8)
    }

    @Test
    func readsNoFillForALayerThatCarriesItsOwnColours() throws {
        let folder = try write(#"{"groups":[{"layers":[{"image-name":"page.svg","name":"page"}]}]}"#)
        let document = try IconComposerDocument.read(at: folder)

        #expect(document.groups[0].layers[0].fill == nil)
    }

    /// A layer that keeps its own colours writes the word `automatic` where
    /// every other layer writes an object. It used to cost the whole document.
    @Test
    func readsNoFillForALayerWhoseFillIsTheWordAutomatic() throws {
        let folder = try write("""
        {"groups":[{"layers":[
          {"image-name":"page.svg","name":"page","fill":"automatic"},
          {"image-name":"mark.svg","name":"mark","fill":{"solid":"srgb:1.00000,1.00000,1.00000,1.00000"}}
        ]}]}
        """)

        // Bottom first, so the layer with the solid fill comes back first.
        let document = try IconComposerDocument.read(at: folder)
        let layers = document.groups[0].layers

        #expect(layers.map(\.imageURL.lastPathComponent) == ["mark.svg", "page.svg"])
        #expect(layers[0].fill != nil)
        #expect(layers[1].fill == nil)
    }

    @Test
    func readsAColourInAnExtendedSpace() throws {
        let folder = try write("""
        {"fill":{"solid":"extended-srgb:0.00000,0.53333,1.00000,1.00000"},"groups":[]}
        """)

        let document = try IconComposerDocument.read(at: folder)
        guard case let .solid(colour) = document.background else {
            Issue.record("Expected a solid background.")
            return
        }

        #expect(colour.green == 0.53333)
        #expect(colour.space == .extendedSRGB)
    }

    /// A grey writes one component and an alpha rather than three and an alpha.
    @Test
    func readsAGreyAsThreeComponentsOfTheSameNumber() throws {
        let folder = try write(#"{"fill":{"solid":"extended-gray:0.50000,1.00000"},"groups":[]}"#)

        let document = try IconComposerDocument.read(at: folder)
        guard case let .solid(colour) = document.background else {
            Issue.record("Expected a solid background.")
            return
        }

        #expect(colour.red == 0.5)
        #expect(colour.green == 0.5)
        #expect(colour.blue == 0.5)
        #expect(colour.alpha == 1)
    }

    /// A space this does not know is still a colour. Reading it as sRGB keeps
    /// the icon, where refusing it would lose the fill.
    @Test
    func readsAColourInASpaceItDoesNotKnowAsSRGB() throws {
        let folder = try write(#"{"fill":{"solid":"rec2020:1.00000,0.00000,0.00000,1.00000"},"groups":[]}"#)

        let document = try IconComposerDocument.read(at: folder)
        guard case let .solid(colour) = document.background else {
            Issue.record("Expected a solid background.")
            return
        }

        #expect(colour.red == 1)
        #expect(colour.space == .sRGB)
    }

    // MARK: - Placement

    @Test
    func readsTheScaleAndTheOffsetOfALayer() throws {
        let folder = try write("""
        {"groups":[{"position":{"scale":2,"translation-in-points":[8,0]},"layers":[
          {"image-name":"page.svg","name":"page","position":{"scale":1.2,"translation-in-points":[-4,16]}}
        ]}]}
        """)

        let document = try IconComposerDocument.read(at: folder)
        let group = document.groups[0]

        #expect(group.placement.scale == 2)
        #expect(group.placement.offset == CGPoint(x: 8, y: 0))
        #expect(group.layers[0].placement.scale == 1.2)
        #expect(group.layers[0].placement.offset == CGPoint(x: -4, y: 16))
    }

    @Test
    func leavesALayerThatSaysNothingWhereItIs() throws {
        let folder = try write(#"{"groups":[{"layers":[{"image-name":"page.svg","name":"page"}]}]}"#)
        let document = try IconComposerDocument.read(at: folder)

        #expect(document.groups[0].placement.scale == 1)
        #expect(document.groups[0].placement.offset == .zero)
        #expect(document.groups[0].layers[0].opacity == 1)
    }
}
