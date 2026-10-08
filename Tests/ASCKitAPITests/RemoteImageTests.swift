import Foundation
import Testing
@testable import ASCKitAPI

/// The address App Store Connect answers with is a template, and what goes in
/// it is a box the image is fitted inside. A box of another shape than the
/// image would show the image smaller than the room it has.
struct RemoteImageTests {
    private let template = "https://example.com/image/thumb/abc/source/{w}x{h}bb.{f}"

    @Test func fitsTheBoxToTheShapeOfTheImage() {
        let image = RemoteImage(template: template, width: 1290, height: 2796)

        #expect(image.url(pixelHeight: 480)?.absoluteString
            == "https://example.com/image/thumb/abc/source/221x480bb.png")
    }

    /// A landscape image is wider than the box is tall, and the width says so.
    @Test func keepsALandscapeImageWide() {
        let image = RemoteImage(template: template, width: 2796, height: 1290)

        #expect(image.url(pixelHeight: 480)?.absoluteString
            == "https://example.com/image/thumb/abc/source/1040x480bb.png")
    }

    /// An image that names no size still has an address. A square box is the
    /// one guess that cuts nothing off, because the image is fitted inside it.
    @Test func asksForASquareBoxWhenTheSizeIsUnknown() {
        let image = RemoteImage(template: template, width: nil, height: nil)

        #expect(image.url(pixelHeight: 480)?.absoluteString
            == "https://example.com/image/thumb/abc/source/480x480bb.png")
    }

    /// Some templates name the way the image is fitted and some ask for it.
    @Test func fillsInHowTheImageIsFitted() {
        let image = RemoteImage(
            template: "https://example.com/image/thumb/abc/source/{w}x{h}{c}.{f}",
            width: 1290,
            height: 2796
        )

        #expect(image.url(pixelHeight: 480)?.absoluteString
            == "https://example.com/image/thumb/abc/source/221x480bb.png")
    }

    @Test func answersNothingForABoxOfNoHeight() {
        let image = RemoteImage(template: template, width: 1290, height: 2796)

        #expect(image.url(pixelHeight: 0) == nil)
    }
}
