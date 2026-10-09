import ASCKitAPI
import Foundation

/// The one configuration file a project holds, usually at `asckit/asckit.json`.
///
/// The language list and the device classes live here, so every project sets
/// its own and the tool needs no change to serve a different app.
public struct ProjectConfig: Codable, Sendable, Hashable {
    public var bundleID: String
    public var keyID: String
    public var issuerID: String?

    /// The language every other language is translated from.
    public var sourceLocale: String

    public var locales: [String]

    /// Languages this project lists and does not write to App Store Connect.
    ///
    /// An app is often translated into more languages than its store page is.
    /// The Xcode project ships Romanian, nobody wrote a Romanian store page,
    /// and nobody wants one. Without this, that language is either missing from
    /// the list, which makes the checker ask for it on every run, or in the
    /// list, which makes it a language with no words and no pictures.
    ///
    /// A name here stays in `locales`, so the checker knows the app is built in
    /// it and says nothing about it. Nothing is written for it, nothing is
    /// checked about it, and the sidebar shows it at the bottom marked Ignored,
    /// so the decision is visible and can be taken back.
    public var ignoredLocales: [String]

    public var deviceClasses: [String]

    /// Which platform's listing this project writes: `ios`, `macos`, `tvos` or
    /// `visionos`.
    ///
    /// Left out for an app on one platform, which is most apps. App Store
    /// Connect then answers with whichever version the app has. An app sold as
    /// a universal purchase has a version per platform, and this says which of
    /// them the words in this folder belong to.
    ///
    /// Held as a string for the reason `deviceClasses` is: a name nobody
    /// recognises is reported by the validator rather than taking the project
    /// down with it.
    public var platform: String?

    /// Languages that show the source language's screenshots, listed by device
    /// class: `{"de-DE": ["ipad-13"]}`.
    ///
    /// App Store Connect shows the primary language's screenshots for any
    /// localization that has none of its own, one display type at a time. So a
    /// language named here is a decision rather than a gap: nothing is missing,
    /// nothing is uploaded, and the check says nothing about it.
    ///
    /// Per device class, because the store falls back per display type. A
    /// language can have its own iPhone screenshots, where the text in the
    /// picture matters, and show the English iPad ones.
    public var usesSourceScreenshots: [String: [String]]

    /// Languages that take the screenshots of the language beside them, listed
    /// by device class: `{"es-ES": {"ipad-13": "es-MX"}}`.
    ///
    /// `es-ES` and `es-MX` read the same pictures, and an export lands in one
    /// of them. `SiblingScreenshots` writes a copy here when it makes one,
    /// because the copy says how the app is translated rather than what one
    /// release holds. `VersionSeed` reads it, so a new version folder starts
    /// with the same copy. `Inbox` reads it, so pictures filed into `es-MX`
    /// land in `es-ES` too.
    public var copiesScreenshotsFrom: [String: [String: String]]

    /// Languages that show the source language's header and search results
    /// art: `["en-GB"]`.
    ///
    /// App Store Connect shows the primary language's art on a language with
    /// none, so nothing is uploaded for them. A language with files of its own
    /// shows its own.
    public var usesSourceCreative: [String]

    /// The country a price is written in before a curve spreads it out, as a
    /// three-letter code.
    ///
    /// A product may name its own. This is what a new one starts with.
    public var baseTerritory: String

    /// The curve a product uses when it does not name one.
    ///
    /// Held as a string for the reason `deviceClasses` is: a name nobody
    /// recognises is reported by the validator rather than taking the project
    /// down with it.
    public var defaultPriceCurve: String

    /// Where the versions live, relative to the configuration file.
    public var versionsPath: String
    public var historyPath: String

    /// Where the in-app purchases live. Beside the configuration file rather
    /// than inside a version, because a product is not tied to a version.
    public var productsPath: String

    private enum CodingKeys: String, CodingKey {
        case bundleID = "bundleId"
        case keyID = "keyId"
        case issuerID = "issuerId"
        case sourceLocale, locales, ignoredLocales, deviceClasses, platform
        case usesSourceScreenshots, copiesScreenshotsFrom, usesSourceCreative
        case baseTerritory, defaultPriceCurve
        case versionsPath, historyPath, productsPath
    }

    public init(
        bundleID: String,
        keyID: String,
        issuerID: String? = nil,
        sourceLocale: String = "en-US",
        locales: [String] = ["en-US"],
        ignoredLocales: [String] = [],
        deviceClasses: [String] = [DeviceClass.iPhone69.id],
        platform: String? = nil,
        usesSourceScreenshots: [String: [String]] = [:],
        copiesScreenshotsFrom: [String: [String: String]] = [:],
        usesSourceCreative: [String] = [],
        baseTerritory: String = "USA",
        defaultPriceCurve: String = PriceCurve.appleEqualized.id,
        versionsPath: String = "versions",
        historyPath: String = "history",
        productsPath: String = "products"
    ) {
        self.bundleID = bundleID
        self.keyID = keyID
        self.issuerID = issuerID
        self.sourceLocale = sourceLocale
        self.locales = locales
        self.ignoredLocales = ignoredLocales
        self.deviceClasses = deviceClasses
        self.platform = platform
        self.usesSourceScreenshots = usesSourceScreenshots
        self.copiesScreenshotsFrom = copiesScreenshotsFrom
        self.usesSourceCreative = usesSourceCreative
        self.baseTerritory = baseTerritory
        self.defaultPriceCurve = defaultPriceCurve
        self.versionsPath = versionsPath
        self.historyPath = historyPath
        self.productsPath = productsPath
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        bundleID = try container.decode(String.self, forKey: .bundleID)
        keyID = try container.decode(String.self, forKey: .keyID)
        issuerID = try container.decodeIfPresent(String.self, forKey: .issuerID)
        sourceLocale = try container.decodeIfPresent(String.self, forKey: .sourceLocale) ?? "en-US"
        locales = try container.decodeIfPresent([String].self, forKey: .locales) ?? [sourceLocale]
        ignoredLocales = try container.decodeIfPresent([String].self, forKey: .ignoredLocales) ?? []
        deviceClasses = try container.decodeIfPresent([String].self, forKey: .deviceClasses)
            ?? [DeviceClass.iPhone69.id]
        platform = try container.decodeIfPresent(String.self, forKey: .platform)
        usesSourceScreenshots = try container.decodeIfPresent(
            [String: [String]].self, forKey: .usesSourceScreenshots
        ) ?? [:]
        copiesScreenshotsFrom = try container.decodeIfPresent(
            [String: [String: String]].self, forKey: .copiesScreenshotsFrom
        ) ?? [:]
        usesSourceCreative = try container.decodeIfPresent([String].self, forKey: .usesSourceCreative) ?? []
        baseTerritory = try container.decodeIfPresent(String.self, forKey: .baseTerritory) ?? "USA"
        defaultPriceCurve = try container.decodeIfPresent(String.self, forKey: .defaultPriceCurve)
            ?? PriceCurve.appleEqualized.id
        versionsPath = try container.decodeIfPresent(String.self, forKey: .versionsPath) ?? "versions"
        historyPath = try container.decodeIfPresent(String.self, forKey: .historyPath) ?? "history"
        productsPath = try container.decodeIfPresent(String.self, forKey: .productsPath) ?? "products"
    }

    /// An individual key has no issuer id, which is how the two are told apart.
    public var usesIndividualKey: Bool { issuerID == nil }

    /// Whether this language shows the source language's screenshots for this
    /// device class, rather than having any of its own.
    public func usesSourceScreenshots(locale: String, deviceClassID: String) -> Bool {
        usesSourceScreenshots[locale]?.contains(deviceClassID) == true
    }

    /// The language this one takes its screenshots from for this device class,
    /// or nil when nobody made that copy.
    public func screenshotDonor(locale: String, deviceClassID: String) -> String? {
        copiesScreenshotsFrom[locale]?[deviceClassID]
    }

    /// The language whose header and search results art this one shows, or
    /// nil when it shows its own.
    public func creativeSource(locale: String) -> String? {
        locale != sourceLocale && usesSourceCreative.contains(locale) ? sourceLocale : nil
    }

    /// `creativeSource(locale:)` for every language that has one.
    public var creativeSources: [String: String] {
        var sources: [String: String] = [:]
        for locale in usesSourceCreative {
            sources[locale] = creativeSource(locale: locale)
        }
        return sources
    }

    /// Whether this language is a variant of the source language, such as
    /// `en-GB` where the source is `en-US`. Those languages read the same
    /// words, so one can show the other's screenshots.
    ///
    /// Answers true for the source language itself. A caller that means
    /// "another language like this one" needs its own `locale != sourceLocale`
    /// guard.
    public func sharesSourceLanguage(_ locale: String) -> Bool {
        StoreLocale.baseLanguage(of: locale) == StoreLocale.baseLanguage(of: sourceLocale)
    }

    /// Whether words this language took from the source language, character
    /// for character, are worth a warning.
    ///
    /// One rule for the listing and for the in-app purchases, so a person sees
    /// the same warning for the same reason in both places.
    ///
    /// The source language is never warned about, because it is the one the
    /// words come from. A language that shares the source language's base, such
    /// as `en-GB` beside `en-US`, is never warned about either: those two read
    /// the same words, so the same words in both is the answer rather than the
    /// problem. Every other language is expected to write the field itself,
    /// unless the field says otherwise, which is what a web address does.
    public func warnsAboutCopiedText(_ field: some LocalizedField, in locale: String) -> Bool {
        guard sharesSourceLanguage(locale) == false else { return false }
        return field.needsItsOwnWords
    }

    /// The device classes this project ships, in the order it lists them.
    /// Unknown names are left to the validator to report.
    public var resolvedDeviceClasses: [DeviceClass] {
        deviceClasses.compactMap(DeviceClass.named)
    }

    /// Whether this project ships screenshots for this device class.
    public func ships(_ deviceClass: DeviceClass) -> Bool {
        deviceClasses.contains(deviceClass.id)
    }

    /// The platform whose device classes this project ships pictures for.
    ///
    /// The one this project names, because that is somebody's decision. Then
    /// the fallback, which is what App Store Connect answered with or what the
    /// Xcode project builds for. Then iOS, which is most apps and is the best
    /// guess while nothing has been read.
    public func screenshotPlatform(fallback: Platform? = nil) -> Platform {
        resolvedPlatform ?? fallback ?? .ios
    }

    /// Every device class the screenshots page shows.
    ///
    /// Every one App Store Connect takes for this platform, whether the project
    /// ships it or not, so an empty slot on the store is an empty slot here
    /// rather than a row that is missing. Plus any class this project lists
    /// from another platform, because a list somebody wrote is a decision.
    ///
    /// Table order, which is the order App Store Connect reads down.
    public func shownDeviceClasses(fallbackPlatform: Platform? = nil) -> [DeviceClass] {
        let platform = screenshotPlatform(fallback: fallbackPlatform)
        return DeviceClass.all.filter { $0.platform == platform || ships($0) }
    }

    /// Whether this project leaves this language to App Store Connect.
    public func isIgnored(_ locale: String) -> Bool {
        ignoredLocales.contains(locale)
    }

    /// The languages this project writes, in the order the list holds them.
    ///
    /// Everything that checks a language, plans a change to one, or writes one
    /// reads this rather than `locales`. `locales` is every language the app
    /// ships, which is what the Xcode check compares against.
    public var writtenLocales: [String] {
        locales.filter { isIgnored($0) == false }
    }

    public var translatedLocales: [String] {
        writtenLocales.filter { $0 != sourceLocale }
    }

    /// The default curve, as far as it is a name ASCKit knows. An unknown name
    /// reads as nil here and is reported by the validator, so nothing
    /// downstream has to decide what a curve it cannot place means.
    public var resolvedDefaultPriceCurve: PriceCurve? {
        PriceCurve.named(defaultPriceCurve)
    }

    /// The platform, as far as it is a name ASCKit knows.
    ///
    /// Nil when the project names none, which asks App Store Connect for every
    /// version the app has. Nil as well for a name it cannot place, which the
    /// validator reports.
    public var resolvedPlatform: Platform? {
        platform.flatMap(Platform.named)
    }

    public var resolvedBaseTerritory: Territory? {
        Territory.named(baseTerritory)
    }
}
