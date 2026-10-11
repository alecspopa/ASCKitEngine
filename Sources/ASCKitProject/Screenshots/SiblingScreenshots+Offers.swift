import ASCKitAPI
import Foundation

extension SiblingScreenshots {
    /// Every language that could take a newer set from the language beside it.
    ///
    /// Sorted by language and then by device class, so a list reads the same
    /// way twice.
    public static func offers(in content: VersionContent, config: ProjectConfig) -> [Offer] {
        var offers: [Offer] = []

        for deviceClass in config.resolvedDeviceClasses {
            for group in groups(in: config) where group.count > 1 {
                for locale in group {
                    let found = offer(
                        for: locale,
                        among: group,
                        deviceClassID: deviceClass.id,
                        content: content,
                        config: config
                    )
                    if let found { offers.append(found) }
                }
            }
        }

        return offers.sorted { ($0.locale, $0.deviceClassID) < ($1.locale, $1.deviceClassID) }
    }

    /// The offer for one language and one device class, or nil when there is
    /// nothing worth copying.
    public static func offer(
        locale: String,
        deviceClassID: String,
        in content: VersionContent,
        config: ProjectConfig
    ) -> Offer? {
        let group = groups(in: config).first { $0.contains(locale) } ?? []
        guard group.count > 1 else { return nil }
        return offer(
            for: locale,
            among: group,
            deviceClassID: deviceClassID,
            content: content,
            config: config
        )
    }

    /// The languages of this project gathered by base language, each group in
    /// alphabetical order.
    ///
    /// `zh-Hans` and `zh-Hant` land in separate groups. A different script is a
    /// different picture, and `StoreLocale.baseLanguage` keeps them apart.
    private static func groups(in config: ProjectConfig) -> [[String]] {
        Dictionary(grouping: config.writtenLocales, by: StoreLocale.baseLanguage)
            .values
            .map { $0.sorted() }
            .sorted { ($0.first ?? "") < ($1.first ?? "") }
    }

    static func offer(
        for locale: String,
        among group: [String],
        deviceClassID: String,
        content: VersionContent,
        config: ProjectConfig
    ) -> Offer? {
        // A language set to show the source language's screenshots has an empty
        // folder on purpose. Nothing is missing, so nothing is offered.
        guard config.usesSourceScreenshots(locale: locale, deviceClassID: deviceClassID) == false else {
            return nil
        }

        let mine = content.screenshots(locale: locale, deviceClassID: deviceClassID)
        let mineNewest = newestDate(of: mine)
        var best: Offer?

        for other in group where other != locale {
            guard config.usesSourceScreenshots(locale: other, deviceClassID: deviceClassID) == false else {
                continue
            }

            let theirs = content.screenshots(locale: other, deviceClassID: deviceClassID)
            guard theirs.isEmpty == false, let theirNewest = newestDate(of: theirs) else { continue }

            // Strictly newer. One export written into both folders lands on the
            // same second in each, and there is nothing to copy between them.
            if let mineNewest, theirNewest <= mineNewest { continue }

            // A date can move without the pictures changing, from a checkout or
            // a re-save. The bytes are what say the two sets really differ.
            guard sameFiles(mine, theirs) == false else { continue }

            if let found = best, found.newest >= theirNewest { continue }
            best = Offer(
                locale: locale,
                from: other,
                deviceClassID: deviceClassID,
                fileCount: theirs.count,
                newest: theirNewest,
                current: mineNewest
            )
        }

        return best
    }

    /// When a set was last written, which is the newest file in it.
    private static func newestDate(of files: [ScreenshotFile]) -> Date? {
        files.compactMap(\.modifiedAt).max()
    }

    /// Whether two sets hold the same pictures under the same names.
    ///
    /// Size first, because it is already in memory. Two files of a different
    /// size cannot be one file, and reading every image to learn that would
    /// make the offer cost as much as the copy.
    private static func sameFiles(_ mine: [ScreenshotFile], _ theirs: [ScreenshotFile]) -> Bool {
        guard mine.count == theirs.count else { return false }

        // A set can hold two files showing one thing, so the first wins rather
        // than the dictionary trapping on a repeated key.
        let byImageName = Dictionary(
            theirs.map { (ScreenshotNaming.imageName(of: $0.fileName), $0) },
            uniquingKeysWith: { first, _ in first }
        )

        var checksums = ChecksumCache()
        for file in mine {
            // A file that cannot be read has no fingerprint. The two sets then
            // count as different, which offers the copy rather than hiding a
            // file nobody can read.
            guard
                let twin = byImageName[ScreenshotNaming.imageName(of: file.fileName)],
                file.byteCount == twin.byteCount,
                file.pixelWidth == twin.pixelWidth,
                file.pixelHeight == twin.pixelHeight,
                let mineDigest = checksums.md5(of: file.url),
                let theirDigest = checksums.md5(of: twin.url),
                mineDigest == theirDigest
            else {
                return false
            }
        }
        return true
    }
}
