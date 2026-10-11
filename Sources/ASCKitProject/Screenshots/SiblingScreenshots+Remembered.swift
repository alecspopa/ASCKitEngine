import ASCKitAPI
import Foundation

extension SiblingScreenshots {
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
                at: .version(version),
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
