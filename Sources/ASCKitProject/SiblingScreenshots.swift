import Foundation

/// Finding the language next door that got the newer screenshots, and copying
/// them across.
///
/// `es-ES` and `es-MX` read the same pictures. A new export usually lands in
/// one of them, and the other keeps last month's. The check says the older one
/// has drifted from the source language, and it is right, but the answer is not
/// in the source language. It is in the language beside it.
///
/// Only inside one base language. The `en-US` screenshots are English pictures,
/// and copying them into `es-ES` would publish a Spanish listing with English
/// artwork. App Store Connect already does that by itself wherever a language
/// has no screenshots, and saying it on purpose is what the checkbox in
/// `usesSourceScreenshots` is for.
///
/// A copy is a decision about how the app is translated, so it is written into
/// `copiesScreenshotsFrom`. It is made again when pictures are filed into the
/// language it comes from, and when a version folder is made.
public enum SiblingScreenshots {
    /// One language that could take another language's screenshots.
    public struct Offer: Sendable, Hashable, Identifiable {
        /// The language that is behind.
        public let locale: String

        /// The language beside it holding the newer set.
        public let from: String

        public let deviceClassID: String

        /// How many files would land in `locale`.
        public let fileCount: Int

        /// When the newer set was last written.
        public let newest: Date

        /// When this language's set was last written. Nil when it has none.
        public let current: Date?

        public var id: String { "\(locale)|\(deviceClassID)|\(from)" }

        public init(
            locale: String,
            from: String,
            deviceClassID: String,
            fileCount: Int,
            newest: Date,
            current: Date?
        ) {
            self.locale = locale
            self.from = from
            self.deviceClassID = deviceClassID
            self.fileCount = fileCount
            self.newest = newest
            self.current = current
        }

        /// The device class as a person reads it, falling back to the id for a
        /// name ASCKit does not know.
        public var deviceName: String {
            DeviceClass.named(deviceClassID)?.displayName ?? deviceClassID
        }

        /// What the copy would do, in one line.
        public var summary: String { String(localized: summaryResource) }

        private var summaryResource: LocalizedStringResource {
            if current == nil {
                LocalizedStringResource("""
                \(locale) has no \(deviceName) screenshots. \
                \(from) has \(fileCount) screenshots, and reads the same words.
                """, bundle: .here)
            } else {
                LocalizedStringResource("""
                The \(from) \(deviceName) screenshots are newer than the \(locale) ones. \
                Copying brings \(fileCount) screenshots across.
                """, bundle: .here)
            }
        }
    }

    // MARK: - What is on offer

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

    private static func offer(
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

        var digests: [URL: String] = [:]
        for file in mine {
            guard
                let twin = byImageName[ScreenshotNaming.imageName(of: file.fileName)],
                file.byteCount == twin.byteCount,
                file.pixelWidth == twin.pixelWidth,
                file.pixelHeight == twin.pixelHeight,
                let mineDigest = digest(of: file.url, into: &digests),
                let theirDigest = digest(of: twin.url, into: &digests),
                mineDigest == theirDigest
            else {
                return false
            }
        }
        return true
    }

    /// A file that cannot be read has no fingerprint. Answering nil makes the
    /// two sets count as different, which offers the copy rather than hiding a
    /// file nobody can read.
    private static func digest(of url: URL, into digests: inout [URL: String]) -> String? {
        if let known = digests[url] { return known }
        guard let made = try? FileChecksum.md5(of: url) else { return nil }
        digests[url] = made
        return made
    }

    // MARK: - Taking one

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
            version: version,
            in: project
        ).files

        // After the files, so a copy that was refused is never remembered.
        try remember(from: donor, to: locale, deviceClassID: deviceClassID, in: project)
        return files
    }

    // MARK: - Remembering one

    private static func remember(
        from donor: String,
        to locale: String,
        deviceClassID: String,
        in project: Project
    ) throws {
        try change(project) { config in
            config.copiesScreenshotsFrom[locale, default: [:]][deviceClassID] = donor

            // The newer export landed in `donor` this time. Two languages that
            // copy each other copy nothing, so the older direction goes.
            if config.copiesScreenshotsFrom[donor]?[deviceClassID] == locale {
                config.copiesScreenshotsFrom[donor]?[deviceClassID] = nil
            }
            if config.copiesScreenshotsFrom[donor]?.isEmpty == true {
                config.copiesScreenshotsFrom[donor] = nil
            }
        }
    }

    /// Takes one copy out of `copiesScreenshotsFrom`, so a new version folder
    /// stops making it. The files stay as they are.
    @discardableResult
    public static func forget(
        locale: String,
        deviceClassID: String,
        in project: Project
    ) throws -> ProjectConfig {
        try change(project) { config in
            config.copiesScreenshotsFrom[locale]?[deviceClassID] = nil
            // The key goes when the last device class does, as it does in
            // `usesSourceScreenshots`.
            if config.copiesScreenshotsFrom[locale]?.isEmpty == true {
                config.copiesScreenshotsFrom[locale] = nil
            }
        }
    }

    /// Reads the configuration file again before writing it.
    ///
    /// A caller that makes several copies holds one read of the folder for all
    /// of them. Writing from that read would keep the last copy and drop the
    /// rest.
    @discardableResult
    private static func change(
        _ project: Project,
        _ body: (inout ProjectConfig) -> Void
    ) throws -> ProjectConfig {
        let before = try Project.load(at: project.configURL).config
        var config = before
        body(&config)
        if config != before { try project.write(config) }
        return config
    }

    // MARK: - Making the remembered copies

    /// One copy that `copiesScreenshotsFrom` names, made in a version folder.
    public struct Remembered: Sendable, Equatable {
        public let locale: String
        public let from: String
        public let deviceClass: DeviceClass
        public let count: Int

        /// How many files of `locale` went to the Trash.
        public let trashed: Int
    }

    /// Makes the copies that `copiesScreenshotsFrom` names, in one version.
    ///
    /// `VersionSeed` calls it for a folder it just filled. App Store Connect
    /// holds a set for each language, so a copy somebody made and never
    /// published is not in the new version.
    ///
    /// `Inbox` and other callers call it after they file pictures, and name
    /// the sets that changed. Only a language that copies one of those sets is
    /// looked at, so filing German pictures never moves a Spanish file.
    ///
    /// A copy is made only where an offer stands: the other language holds a
    /// newer set, or this language holds none. A language that got the newer
    /// export itself keeps it, whatever the setting says.
    ///
    /// A copy that cannot be made is left out, and the set stays as it was.
    /// The validator reports a setting that names the wrong thing, and the
    /// Screenshots page still offers a copy that failed.
    public static func copyRemembered(
        version: String,
        in project: Project,
        after changed: Set<ScreenshotSlot>? = nil
    ) throws -> [Remembered] {
        let config = project.config
        let followers = followers(in: config, after: changed)
        guard followers.isEmpty == false else { return [] }

        var content = try ContentStore.load(version: version, in: project)
        var made: [Remembered] = []

        for follower in followers {
            let standing = offer(
                for: follower.locale,
                among: [follower.locale, follower.donor],
                deviceClassID: follower.deviceClass.id,
                content: content,
                config: config
            )
            guard standing != nil else { continue }

            let theirs = content.screenshots(locale: follower.donor, deviceClassID: follower.deviceClass.id)
            let landed = try? ContentWriter.replaceSlot(
                with: theirs.map(\.url),
                locale: follower.locale,
                deviceClass: follower.deviceClass,
                version: version,
                in: project
            )
            guard let landed else { continue }

            made.append(Remembered(
                locale: follower.locale,
                from: follower.donor,
                deviceClass: follower.deviceClass,
                count: landed.files.count,
                trashed: landed.trashed.count
            ))

            // `en-GB` can copy `en-AU`, which copies `en-US`. The next copy
            // takes what this one landed.
            content = try ContentStore.load(version: version, in: project)
        }
        return made
    }

    /// One entry of `copiesScreenshotsFrom` that can be made.
    private struct Follower {
        let locale: String
        let donor: String
        let deviceClass: DeviceClass

        /// How many copies the pictures pass through to get here.
        let distance: Int
    }

    /// The entries that can be made. A language that gives its set comes
    /// before the language that takes it, so a chain is made in order.
    private static func followers(
        in config: ProjectConfig,
        after changed: Set<ScreenshotSlot>?
    ) -> [Follower] {
        var found: [Follower] = []

        for locale in config.copiesScreenshotsFrom.keys {
            for deviceClassID in config.copiesScreenshotsFrom[locale, default: [:]].keys {
                guard
                    let chain = chain(from: locale, deviceClassID: deviceClassID, config: config),
                    let donor = chain.first,
                    let deviceClass = DeviceClass.named(deviceClassID)
                else { continue }

                let follows = { (changed: Set<ScreenshotSlot>) in
                    chain.contains { changed.contains(ScreenshotSlot(locale: $0, deviceClassID: deviceClassID)) }
                }
                if let changed, follows(changed) == false { continue }

                found.append(Follower(
                    locale: locale, donor: donor, deviceClass: deviceClass, distance: chain.count
                ))
            }
        }

        return found.sorted {
            ($0.distance, $0.locale, $0.deviceClass.id) < ($1.distance, $1.locale, $1.deviceClass.id)
        }
    }

    /// The language one copy comes from, or nil for a copy that cannot be
    /// made.
    static func donor(of locale: String, deviceClassID: String, config: ProjectConfig) -> String? {
        chain(from: locale, deviceClassID: deviceClassID, config: config)?.first
    }

    /// The languages a set passes through to get to this one, nearest first.
    /// `en-GB` copies `en-AU`, which copies `en-US`: for `en-GB` that is
    /// `en-AU` and then `en-US`.
    ///
    /// Nil for a copy that cannot be made: a language the project does not
    /// ship, a language that reads different words, a device class the project
    /// does not list, and a chain that comes back to where it started.
    private static func chain(
        from locale: String,
        deviceClassID: String,
        config: ProjectConfig
    ) -> [String]? {
        guard
            config.writtenLocales.contains(locale),
            config.deviceClasses.contains(deviceClassID)
        else { return nil }

        var chain: [String] = []
        var current = locale
        while let next = config.copiesScreenshotsFrom[current]?[deviceClassID] {
            // Two languages that copy each other copy nothing.
            if next == locale { return nil }

            // A wrong entry further along ends the chain. It is that
            // language's copy that cannot be made, and this one still can.
            guard
                chain.contains(next) == false,
                config.writtenLocales.contains(next),
                StoreLocale.baseLanguage(of: next) == StoreLocale.baseLanguage(of: locale)
            else { break }

            chain.append(next)
            current = next
        }
        return chain.isEmpty ? nil : chain
    }
}

public enum SiblingScreenshotError: Error, CustomLocalizedStringResourceConvertible {
    case sameLanguage(String)
    case notShipped(String, shipped: [String])
    case differentLanguage(from: String, to: String)
    case noSuchDeviceClass(String, listed: [String])
    case nothingToCopy(from: String, deviceClassID: String)

    public var localizedStringResource: LocalizedStringResource {
        switch self {
        case let .sameLanguage(locale):
            LocalizedStringResource("\(locale) cannot copy its own screenshots.", bundle: .here)

        case let .notShipped(locale, shipped):
            LocalizedStringResource("""
            \(locale) is not a language this project ships. It ships \
            \(shipped.joined(separator: ", ")).
            """, bundle: .here)

        case let .differentLanguage(from, to):
            LocalizedStringResource("""
            \(from) and \(to) are different languages, so the pictures say different words. \
            Screenshots are copied only between languages such as es-ES and es-MX. \
            To show another language's screenshots, put \(to) in usesSourceScreenshots.
            """, bundle: .here)

        case let .noSuchDeviceClass(identifier, listed):
            LocalizedStringResource("""
            \(identifier) is not a device class this project lists. It lists \
            \(listed.joined(separator: ", ")).
            """, bundle: .here)

        case let .nothingToCopy(from, deviceClassID):
            LocalizedStringResource("\(from) has no \(deviceClassID) screenshots to copy.", bundle: .here)
        }
    }
}

extension SiblingScreenshotError: CustomStringConvertible {
    public var description: String { String(localized: localizedStringResource) }
}
