import ASCKitAPI
import Foundation

extension SiblingScreenshots {
    /// Copies one offer, so the language that was behind holds exactly what the
    /// language beside it holds.
    @discardableResult
    public static func accept(
        _ offer: Offer,
        version: String,
        in project: Project
    ) throws -> [ScreenshotFile] {
        try copy(
            from: offer.from,
            to: offer.locale,
            deviceClassID: offer.deviceClassID,
            version: version,
            in: project
        )
    }

    /// Copies one device class of screenshots from one language to another.
    ///
    /// The two languages have to be the same language. Everything the target
    /// held goes to the Trash, so afterwards the two folders hold the same
    /// pictures in the same order.
    ///
    /// The copy is written into `copiesScreenshotsFrom`, so `copyRemembered`
    /// makes it again from then on.
    @discardableResult
    public static func copy(
        from donor: String,
        to locale: String,
        deviceClassID: String,
        version: String,
        in project: Project
    ) throws -> [ScreenshotFile] {
        let config = project.config

        guard donor != locale else { throw SiblingScreenshotError.sameLanguage(locale) }
        for code in [donor, locale] where config.writtenLocales.contains(code) == false {
            throw SiblingScreenshotError.notShipped(code, shipped: config.writtenLocales)
        }
        guard StoreLocale.baseLanguage(of: donor) == StoreLocale.baseLanguage(of: locale) else {
            throw SiblingScreenshotError.differentLanguage(from: donor, to: locale)
        }
        guard
            config.deviceClasses.contains(deviceClassID),
            let deviceClass = DeviceClass.named(deviceClassID)
        else {
            throw SiblingScreenshotError.noSuchDeviceClass(deviceClassID, listed: config.deviceClasses)
        }

        // Read again rather than taking a list from the caller. The offer may
        // be minutes old, and what lands is what the donor holds now.
        let donorFiles = try ContentStore.load(version: version, in: project)
            .screenshots(locale: donor, deviceClassID: deviceClassID)
        guard donorFiles.isEmpty == false else {
            throw SiblingScreenshotError.nothingToCopy(from: donor, deviceClassID: deviceClassID)
        }

        let files = try ContentWriter.replaceSlot(
            with: donorFiles.map(\.url),
            locale: locale,
            deviceClass: deviceClass,
            at: .version(version),
            in: project
        ).files

        // After the files, so a copy that was refused is never remembered.
        try remember(from: donor, to: locale, deviceClassID: deviceClassID, in: project)
        return files
    }
}
