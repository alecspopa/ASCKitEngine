import ASCKitAPI
import Foundation

/// What an `.xcodeproj` says about the app it builds.
///
/// The Xcode project already knows the app's name, its bundle identifier, the
/// version being worked on and the languages it ships. Asking a person to type
/// all of that again is asking them to get it wrong, and to keep it in step by
/// hand forever after.
///
/// Read straight out of the project file. Xcode 27.2 writes `project.xcproj`,
/// which is JSON5. Every Xcode before it writes `project.pbxproj`, which is an
/// old-style property list. Both are read here, and both give the same answers.
///
/// Running `xcodebuild -showBuildSettings` would resolve every setting
/// properly, but it is slow and a sandboxed app cannot run it. So the parts of
/// that resolution which matter are done here: a target inherits from the
/// project, a value may point at another value, and an older project keeps its
/// name and version in an `Info.plist` rather than in a build setting.
public struct XcodeProject: Sendable {
    /// The `.xcodeproj` bundle itself.
    public let url: URL

    /// Languages the app is built in, as Xcode writes them: `en`, `de`, `fr`.
    /// Not App Store locale codes, and not translated into them here.
    ///
    /// The development language first, out of whichever file was read. A
    /// listing is written in one language and translated into the rest, and
    /// the front of this list is what says which language that is.
    public let knownRegions: [String]

    /// The app targets, ignoring tests, extensions and everything that is not
    /// a thing the App Store lists.
    public let apps: [App]

    public struct App: Sendable, Identifiable, Hashable {
        public let targetName: String
        public let bundleID: String?

        /// The version string App Store Connect shows. `MARKETING_VERSION`,
        /// or `CFBundleShortVersionString` for a project old enough to keep it
        /// in an `Info.plist`.
        ///
        /// Nil when it is set somewhere this cannot see, such as an `.xcconfig`
        /// file or a script that rewrites it at build time.
        public let marketingVersion: String?

        /// What a person calls the app.
        public let displayName: String

        /// The name of the icon set in the asset catalog, usually `AppIcon`.
        /// The name only. Finding the picture means walking the folder, which
        /// `AppIcon.find` does and this deliberately does not.
        public let iconName: String?

        /// The platform this target builds for, read from `SDKROOT`.
        ///
        /// Nil for a target that builds for whichever platform it is told to,
        /// and for a setting this cannot see. It says which screenshot sizes a
        /// new project starts with, so a Mac app is not asked for iPhone ones.
        public let platform: Platform?

        public var id: String { targetName }
    }

    /// The target a listing belongs to.
    ///
    /// The one building that bundle identifier. Failing that, the only app in
    /// the project, because a project building one app has one answer whatever
    /// the configuration says.
    ///
    /// The bundle identifier is optional, for a caller holding a folder and
    /// nothing else, such as the list of projects the launcher offers.
    ///
    /// Nil for a project building several apps, none of them this one. Guessing
    /// there would put another app's name and icon on this listing.
    public func app(forBundleID bundleID: String?) -> App? {
        if let bundleID, let matched = apps.first(where: { $0.bundleID == bundleID }) { return matched }
        return apps.count == 1 ? apps[0] : nil
    }

    // MARK: - Finding one

    /// The `.xcodeproj` in a folder, if there is exactly one.
    ///
    /// More than one is left alone rather than guessed at: a folder holding two
    /// Xcode projects has no obvious answer, and picking wrong would scaffold a
    /// listing for the wrong app.
    public static func find(in folderURL: URL) -> URL? {
        let names = DirectoryListing.entries(in: folderURL, keys: [])
            .map(\.lastPathComponent)
            .filter { $0.hasSuffix(".xcodeproj") }
            .sorted()

        // Built from the name rather than handed back as found, because
        // `contentsOfDirectory` marks a directory with a trailing slash and a
        // caller comparing two URLs should not have to know that.
        return names.count == 1 ? folderURL.appending(path: names[0]) : nil
    }

    // MARK: - Reading one

    /// Reads whichever of the two project files the folder holds.
    ///
    /// `project.xcproj` first. A folder holding both files is one part way
    /// through the change of format, and the JSON file is the newer of the two.
    /// A `project.xcproj` that will not parse is reported rather than stepped
    /// around, because a stale `project.pbxproj` beside it would answer with an
    /// old version and an old bundle identifier.
    public static func read(at url: URL) throws -> XcodeProject {
        // Everything a path in a build setting is relative to. `.xcodeproj`
        // sits in it, so its parent is the folder Xcode calls SRCROOT.
        let sourceRoot = url.deletingLastPathComponent()

        if let data = try? Data(contentsOf: url.appending(path: "project.xcproj")) {
            return try readJSON(data, at: url, sourceRoot: sourceRoot)
        }
        if let data = try? Data(contentsOf: url.appending(path: "project.pbxproj")) {
            return try readPropertyList(data, at: url, sourceRoot: sourceRoot)
        }
        throw XcodeProjectError.unreadable(url: url)
    }

    // MARK: - Targets

    static func app(
        id: String,
        in objects: [String: [String: Any]],
        inheriting projectSettings: [String: String],
        sourceRoot: URL
    ) -> App? {
        guard
            let target = objects[id],
            target["isa"] as? String == "PBXNativeTarget",
            target["productType"] as? String == "com.apple.product-type.application",
            let name = target["name"] as? String
        else {
            return nil
        }

        // A target's own settings win, and it inherits the project's for
        // everything it does not set. Xcode's own inheritance in the one form
        // that turns up: a version set once for the whole project.
        var resolved = projectSettings
        resolved.merge(
            settings(ofConfigurationList: target["buildConfigurationList"], in: objects),
            uniquingKeysWith: { _, target in target }
        )
        return app(named: name, settings: resolved, sourceRoot: sourceRoot)
    }

    /// What an app target says about its listing, from the settings that
    /// already apply to it.
    ///
    /// Shared by both formats. Which file a setting came from, and how a target
    /// inherits one, is all the two formats disagree about. Everything after
    /// that is the same work.
    static func app(
        named name: String,
        settings: [String: String],
        sourceRoot: URL
    ) -> App? {
        var resolved = settings
        resolved["TARGET_NAME"] = name
        resolved["PRODUCT_NAME"] = resolved["PRODUCT_NAME"] ?? name

        guard listsOnTheAppStore(resolved) else { return nil }

        // An older project keeps the name and the version in an Info.plist,
        // usually as `$(MARKETING_VERSION)` pointing back at a build setting.
        let plist = infoPlist(from: resolved, sourceRoot: sourceRoot)

        return App(
            targetName: name,
            bundleID: value(
                "PRODUCT_BUNDLE_IDENTIFIER",
                in: resolved,
                orPlist: "CFBundleIdentifier",
                plist: plist
            ),
            marketingVersion: value(
                "MARKETING_VERSION",
                in: resolved,
                orPlist: "CFBundleShortVersionString",
                plist: plist
            ),
            displayName: value(
                "INFOPLIST_KEY_CFBundleDisplayName",
                in: resolved,
                orPlist: "CFBundleDisplayName",
                plist: plist
            )
                ?? value(
                    "INFOPLIST_KEY_CFBundleName",
                    in: resolved,
                    orPlist: "CFBundleName",
                    plist: plist
                )
                ?? resolve(resolved["PRODUCT_NAME"], settings: resolved)
                ?? name,
            iconName: resolve(resolved["ASSETCATALOG_COMPILER_APPICON_NAME"], settings: resolved),
            platform: platform(of: resolved)
        )
    }

    /// The one platform a target builds for, out of `SDKROOT` and
    /// `SUPPORTED_PLATFORMS`.
    ///
    /// `SDKROOT` first, because it names one platform when it names any.
    /// Xcode writes `auto` into it for most targets today, and then
    /// `SUPPORTED_PLATFORMS` is the setting that says which platforms the
    /// target has. A simulator SDK counts as its device SDK, so
    /// `macosx` alone is a Mac app and `iphoneos iphonesimulator macosx` is
    /// not one platform at all.
    ///
    /// Nil for a target that builds for more than one, and for settings this
    /// cannot see. App Store Connect then answers with whichever version the
    /// app has.
    private static func platform(of settings: [String: String]) -> Platform? {
        if let sdk = platform(ofSDK: settings["SDKROOT"] ?? "") { return sdk }

        let supported = (settings["SUPPORTED_PLATFORMS"] ?? "")
            .split(whereSeparator: \.isWhitespace)
            .map { platform(ofSDK: String($0)) }

        guard supported.isEmpty == false, supported.allSatisfy({ $0 != nil }) else { return nil }
        let named = Set(supported.compactMap(\.self))
        return named.count == 1 ? named.first : nil
    }

    /// The platform one SDK name belongs to, taking a simulator SDK as the
    /// device SDK beside it.
    private static func platform(ofSDK name: String) -> Platform? {
        switch name.lowercased() {
        case "macosx": .macOS
        case "iphoneos", "iphonesimulator": .ios
        case "appletvos", "appletvsimulator": .tvOS
        case "xros", "visionos", "xrsimulator", "visionsimulator": .visionOS
        default: nil
        }
    }

    /// A build setting, or the `Info.plist` key that means the same thing.
    ///
    /// The build setting first, because that is what Xcode writes today and it
    /// is what wins at build time when both are there.
    private static func value(
        _ setting: String,
        in settings: [String: String],
        orPlist key: String,
        plist: [String: Any]?
    ) -> String? {
        if let resolved = resolve(settings[setting], settings: settings) { return resolved }
        return resolve(plist?[key] as? String, settings: settings)
    }

    /// An app for a platform the App Store lists. A watch-only app or a driver
    /// extension builds an application too, and neither has a listing of its
    /// own to write.
    private static func listsOnTheAppStore(_ settings: [String: String]) -> Bool {
        let platforms = [settings["SDKROOT"], settings["SUPPORTED_PLATFORMS"]]
            .compactMap(\.self)
            .joined(separator: " ")

        // `auto` means the target builds for whatever it is told to, which
        // includes iOS and macOS. Nothing at all is treated the same way,
        // because a missing setting is not a reason to hide a target.
        guard platforms.isEmpty == false else { return true }
        return platforms.contains("iphoneos")
            || platforms.contains("macosx")
            || platforms.contains("auto")
    }

    // MARK: - Info.plist

    private static func infoPlist(
        from settings: [String: String],
        sourceRoot: URL
    ) -> [String: Any]? {
        guard
            let path = resolve(settings["INFOPLIST_FILE"], settings: settings),
            let data = try? Data(contentsOf: sourceRoot.appending(path: path))
        else {
            return nil
        }
        return try? PropertyListSerialization.propertyList(
            from: data, options: [], format: nil
        ) as? [String: Any]
    }

    // MARK: - Resolving references

    /// Replaces `$(NAME)` and `${NAME}` with what the build settings say.
    ///
    /// `CFBundleShortVersionString = $(MARKETING_VERSION)` is what every recent
    /// template writes, so a version read out of an `Info.plist` is almost
    /// always a reference rather than a number.
    ///
    /// A reference nothing here defines, such as one from an `.xcconfig` file
    /// or from the environment, gives nil. Saying the value is not known beats
    /// handing on a string with a dollar sign still in it, which would be
    /// written into a configuration file and pushed to the App Store.
    static func resolve(_ value: String?, settings: [String: String], depth: Int = 0) -> String? {
        guard let value, value.isEmpty == false else { return nil }
        guard value.contains("$(") || value.contains("${") else { return value }

        // A reference to itself, or a pair pointing at each other. Five rounds
        // is far past anything a real project does.
        guard depth < 5 else { return nil }

        var resolved = value
        for (name, replacement) in settings where replacement.contains(value) == false {
            resolved = resolved
                .replacingOccurrences(of: "$(\(name))", with: replacement)
                .replacingOccurrences(of: "${\(name)}", with: replacement)
        }

        guard resolved != value else { return nil }
        return resolve(resolved, settings: settings, depth: depth + 1)
    }
}
