import ASCKitAPI
import Foundation

public extension ContentWriter {
    // MARK: - Checking one image

    /// Why this device class would refuse this image, or nil when it would take it.
    ///
    /// Public because the reason is worth showing before somebody asks for the
    /// move, not only after it is refused.
    ///
    /// The rules are the validator's: App Store Connect's own sizes and alpha
    /// rule when there is reference data, and the built-in sizes when there is none.
    static func reasonToRefuse(
        _ file: ScreenshotFile,
        for deviceClass: DeviceClass,
        refData: AssetLibraryRefData? = nil
    ) -> String? {
        let rules = ImageRules.screenshot(of: deviceClass, refData: refData)
        guard let width = file.pixelWidth, let height = file.pixelHeight else {
            return String(localized: "\(file.fileName) could not be read as an image.", bundle: .module)
        }
        if rules.accepts(width: width, height: height) == false {
            return String(localized: """
            \(file.fileName) is \(file.pixelDescription). \(deviceClass.displayName) takes \
            \(rules.sizeList), or the same sizes on their side.
            """, bundle: .module)
        }
        if file.hasAlpha == true, rules.alphaAllowed == false {
            return String(localized: """
            \(file.fileName) has an alpha channel. App Store Connect refuses those. \
            Export it again without one. Artwork that looks fully opaque still gets \
            an alpha channel from most design tools.
            """, bundle: .module)
        }
        return nil
    }

    /// Whether the alpha channel is the only thing between this image and that
    /// device class's set.
    ///
    /// `AlphaRemoval` acts on this. An image the right size that carries a
    /// channel can be written again without it and filed as it is, and an image
    /// of the wrong size cannot: clearing that one would change the file and
    /// leave it refused.
    static func onlyTheAlphaChannelRefuses(
        _ file: ScreenshotFile, for deviceClass: DeviceClass, refData: AssetLibraryRefData? = nil
    ) -> Bool {
        guard let width = file.pixelWidth, let height = file.pixelHeight else { return false }
        let rules = ImageRules.screenshot(of: deviceClass, refData: refData)
        return file.hasAlpha == true && rules.alphaAllowed == false && rules.accepts(width: width, height: height)
    }

    /// Why an inbox refuses this waiting screenshot, and whether `AlphaRemoval`
    /// can clear the one reason. Nil when nothing refuses it.
    ///
    /// Every inbox asks this, so each one says a clearable channel in the same
    /// short line and offers the same clear.
    static func inboxRefusal(
        _ file: ScreenshotFile, for deviceClass: DeviceClass, refData: AssetLibraryRefData? = nil
    ) -> (reason: String, hasClearableAlpha: Bool)? {
        guard let reason = reasonToRefuse(file, for: deviceClass, refData: refData) else { return nil }
        // The offer beside the refusal says what to do, so the line does not.
        guard onlyTheAlphaChannelRefuses(file, for: deviceClass, refData: refData) else {
            return (reason, false)
        }
        return (String(localized: "\(file.fileName) has an alpha channel.", bundle: .module), true)
    }
}
