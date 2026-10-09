import Foundation

/// Something wrong with a project, said in a way that names the fix.
public struct Problem: Sendable, Hashable, Identifiable {
    public enum Severity: String, Sendable, Comparable {
        /// Blocks publishing.
        case error
        /// Worth knowing, does not block.
        case warning

        public static func < (lhs: Severity, rhs: Severity) -> Bool {
            lhs == .error && rhs == .warning
        }
    }

    public enum Area: String, Sendable, CaseIterable, Codable {
        case configuration
        case layout
        case appInformation
        case screenshots
        /// An in-app purchase's name, description or review note.
        case products
        /// What an in-app purchase costs, and where.
        case pricing
    }

    /// The rule that made this problem.
    ///
    /// Every problem names its rule, and nothing outside this type reads the
    /// message to work out which one it is. A silenced warning is kept by its
    /// rule, so the silence survives a change of wording and a change of
    /// language. Matching the text would lose it on both.
    ///
    /// The raw value goes into a file, so a case may be added and a case may
    /// be taken away, but a case is never renamed.
    public enum Kind: String, Sendable, Hashable, Codable {
        // MARK: Configuration

        /// A locale in the list is one App Store Connect does not accept.
        case localeNotAccepted
        /// A device class in the list is one ASCKit does not know.
        case deviceClassNotKnown
        /// The platform named is one ASCKit does not know.
        case platformNotKnown
        /// The source language is not one of the languages the project ships.
        case sourceLocaleNotListed
        /// The locale list is empty.
        case noLocalesListed
        /// The device class list is empty.
        case noDeviceClassesListed
        /// One locale is in the list twice.
        case localeListedTwice
        /// An ignored language is not one of the languages the project lists.
        case ignoredLocaleNotListed
        /// The source language is ignored.
        case sourceLocaleIgnored
        /// The source language is set to show its own screenshots.
        case sourceLocaleUsesOwnScreenshots
        /// A language set to show the source language's screenshots is not one
        /// the project ships.
        case sourceScreenshotsLocaleNotShipped
        /// A language set to show the source language's screenshots reads
        /// different words from it.
        case sourceScreenshotsLocaleReadsDifferently
        /// A language is set to show the source language's screenshots for a
        /// device class the project does not list.
        case sourceScreenshotsDeviceClassNotListed
        /// `copiesScreenshotsFrom` names a copy that cannot be made.
        case screenshotCopyCannotBeMade
        /// `usesSourceCreative` names the source language, or a language the
        /// project does not ship.
        case sourceCreativeLocaleNotUsable
        /// `usesSourceCreative` names a language that reads different words
        /// from the source language.
        case sourceCreativeLocaleReadsDifferently
        /// Xcode builds a different bundle id from the one this project pushes
        /// to.
        case bundleIDMismatch
        /// The app is built in a language the listing has no words for.
        case appRegionNotListed
        /// The app is built in a language, and the listing has none of the
        /// codes that language could use.
        case appRegionNoneListed
        /// The country a listing prices from is not one the App Store sells in.
        case baseTerritoryNotKnown
        /// The default price curve is not one ASCKit knows.
        case defaultCurveNotKnown

        // MARK: Layout

        /// An app information file could not be read.
        case appInformationUnreadable
        /// A language the project ships has no app information file.
        case appInformationFileMissing
        /// There is an app information file for a language the project does
        /// not ship.
        case appInformationFileNotListed
        /// An app information file names a different language from its file
        /// name.
        case appInformationLocaleMismatch
        /// There are screenshots for a language the project does not ship.
        case screenshotFolderLocaleNotListed
        /// There are screenshots for a device class the project does not list.
        case screenshotFolderDeviceClassNotListed
        /// Xcode builds a version this project has no folder for.
        case versionFolderMissingForXcode
        /// App Store Connect is on a version this project has no folder for.
        case versionFolderMissingForStore
        /// The project has no version folders at all.
        case noVersionsYet

        // MARK: App information

        /// This language has no words for a field, and the source language has
        /// none either.
        case textMissing
        /// The source language has words here and this language has none.
        case textNotTranslated
        /// This language's words are the source language's, word for word.
        case textMatchesSource
        /// A field is there and holds nothing, which blanks it on the store.
        case textEmpty
        /// A field is longer than App Store Connect accepts.
        case textOverLimit
        /// A field is shorter than App Store Connect accepts.
        case textUnderMinimum
        /// The keywords are separated by a comma and a space, and the space
        /// costs a character.
        case keywordsHaveSpace
        /// A field that has to be a web address is not an https one.
        case urlNotHTTPS
        /// A field starts or ends with a space.
        case textHasEdgeSpace
        /// A language is marked in a way that keeps it off the store.
        case statusNotPublishable

        // MARK: In-app purchases

        /// A product file could not be read.
        case productFileUnreadable
        /// A product file names a different product from its file name.
        case productIDMismatch
        /// A product says it is a kind of purchase ASCKit does not know.
        case productKindNotKnown
        /// A subscription names no group.
        case subscriptionHasNoGroup
        /// A purchase that is not a subscription names a subscription group.
        case nonSubscriptionNamesGroup
        /// A purchase that is not a subscription sets preserveCurrentPrice.
        case nonSubscriptionPreservesPrice
        /// A subscription does not say how long a period is.
        case subscriptionHasNoPeriod
        /// The review note is longer than App Store Connect accepts.
        case reviewNoteOverLimit
        /// A subscription group file could not be read.
        case groupFileUnreadable
        /// A subscription group has no display name in any language.
        case groupHasNoWords
        /// A group file holds a language the project does not ship.
        case groupLocaleNotShipped
        /// A group has words in some languages and no display name in this one.
        case groupTextNotTranslated
        /// A group field is there and holds nothing.
        case groupTextEmpty
        /// A group field is longer than App Store Connect accepts.
        case groupTextOverLimit
        /// A group field starts or ends with a space.
        case groupTextHasEdgeSpace
        /// A product holds words for a language the project does not ship.
        case productLocaleNotShipped
        /// A product's name or description is missing in a language the
        /// project ships.
        case productTextNotTranslated
        /// A product's name or description in this language is the source
        /// language's, word for word.
        case productTextMatchesSource
        /// A product field is there and holds nothing.
        case productTextEmpty
        /// A product field is longer than App Store Connect accepts.
        case productTextOverLimit
        /// A product field starts or ends with a space.
        case productTextHasEdgeSpace

        // MARK: Screenshots

        /// A language set to show the source language's screenshots has some
        /// of its own as well.
        case screenshotsBesideSourceCopy
        /// A set holds more screenshots than App Store Connect accepts.
        case screenshotsOverLimit
        /// A language has no screenshots of its own for a device class, and
        /// nothing says it should fall back.
        case screenshotsMissing
        /// A language has an empty screenshot folder for a device class, so
        /// App Store Connect shows the source language's pictures instead.
        case screenshotsNotTranslated
        /// A language's screenshots are the source language's files, byte for
        /// byte.
        case screenshotsCopiedFromSource
        /// A set is missing the numbers its source language has.
        case screenshotsMissingSiblings
        /// A screenshot is not named the way ASCKit names one.
        case screenshotsNamedWrong
        /// A file in a screenshot folder could not be read as an image.
        case screenshotUnreadable
        /// A screenshot is a size the device class does not accept.
        case screenshotWrongSize
        /// A screenshot carries an alpha channel, which App Store Connect
        /// refuses.
        case screenshotHasAlpha
        /// A screenshot's name does not start with a number, so nothing says
        /// what order the set goes in.
        case screenshotHasNoNumber
        /// A screenshot is a bigger file than App Store Connect takes.
        case screenshotTooLarge
        /// A screenshot is a kind of file App Store Connect does not take.
        case screenshotWrongFileType
        /// An iPhone app lists no iPhone Duo screenshots, which App Store
        /// Connect needs from April 2027.
        case iPhoneDuoMissing

        // MARK: App previews

        /// A preview folder for a device class that takes none, such as a watch.
        case previewDeviceClassTakesNone
        case previewsOverLimit
        case previewWrongFileType
        case previewUnreadable
        case previewWrongSize
        case previewWrongLength
        case previewWrongFrameRate
        /// A fragmented movie, whose frame rate a check cannot read.
        case previewFragmented
        case previewCodecNotAccepted
        case previewTooLarge
        case previewHasNoAudio
        case previewPosterFrameNotValid
        case previewPosterFrameNamesNoFile
        case previewPosterFramesUnreadable

        // MARK: Header and search results

        /// A file in a creative folder that is neither the header nor the
        /// search results art.
        case creativeFileNotKnown
        /// Two files for one role, such as header.png and header.mov.
        case creativeTwoFiles
        case creativeWrongFileType
        case creativeUnreadable
        case creativeWrongSize
        case creativeHasAlpha
        case creativeWrongLength
        case creativeWrongFrameRate
        /// A header with no search results file beside it, in a size that
        /// does not fit search results.
        case creativeHeaderNotUniversal
        /// A language set to show the source language's art has files of its own.
        case creativeBesideSourceCopy

        // MARK: Pricing

        /// A product's base price is not a number.
        case baseAmountNotANumber
        /// A product prices from a country the App Store does not sell in.
        case productBaseTerritoryNotKnown
        /// A product asks for a price curve ASCKit does not know.
        case productCurveNotKnown
        /// A price is set for a country the App Store does not sell in.
        case overrideTerritoryNotKnown
        /// A price names both an amount and a price point, and only one of
        /// them can be meant.
        case overrideSaysBoth
        /// A price says nothing about what to charge.
        case overrideSaysNothing
        /// A price is not a number.
        case overrideAmountNotANumber
        /// A price is set to start on something that is not a date.
        case startDateNotADate
        /// A curve's numbers are older than the numbers App Store Connect
        /// answers with now.
        case curveProceedsDrift
        /// App Store Connect sells somewhere ASCKit's own table does not list,
        /// so no curve can say anything about it and it gets Apple's own price.
        case territoryNotKnown
        /// A territory has no price point anywhere near what the curve asked
        /// for, or none at all.
        case noPricePoint
        /// A price set by hand with no reason written beside it.
        case priceOverrideUnexplained
        /// No instalment of a yearly price works out near a twelfth of it, so
        /// the monthly and yearly prices cannot line up.
        case instalmentNotAvailable
    }

    public let severity: Severity
    public let area: Area

    /// A catalog entry, resolved where it is shown. A validator runs in one
    /// place and its words are read in another, so the sentence travels as a
    /// resource and the reader's language decides what it says.
    public let message: LocalizedStringResource

    /// What to do about it. Nil when the message already says.
    public let fix: LocalizedStringResource?

    public let locale: String?
    public let deviceClassID: String?
    public let field: MetadataField?

    /// The in-app purchase this is about, by the product id in its file name.
    public let productID: String?

    /// The country this is about, as a three-letter code.
    public let territory: String?

    /// A field on a product, which has its own limits and its own two names.
    public let productField: ProductField?

    /// The subscription group this is about, by its reference name.
    public let subscriptionGroup: String?

    public let groupField: GroupField?

    /// Relative to the project root, so it reads the same in every window.
    public let path: String?

    public let kind: Kind

    /// The rule and the thing it is about, which together say which problem
    /// this is. The message says the same thing in words, and the words
    /// change with the reader's language.
    public var id: String {
        var parts = [
            severity.rawValue, area.rawValue, kind.rawValue,
            locale ?? "", deviceClassID ?? "", field?.rawValue ?? "",
            productID ?? "", territory ?? "", productField?.rawValue ?? "",
            path ?? ""
        ]
        // Only when set, so every problem made before groups keeps its id.
        if let subscriptionGroup {
            parts += [subscriptionGroup, groupField?.rawValue ?? ""]
        }
        return parts.joined(separator: "|")
    }

    public init(
        severity: Severity,
        area: Area,
        message: LocalizedStringResource,
        fix: LocalizedStringResource? = nil,
        locale: String? = nil,
        deviceClassID: String? = nil,
        field: MetadataField? = nil,
        productID: String? = nil,
        territory: String? = nil,
        productField: ProductField? = nil,
        subscriptionGroup: String? = nil,
        groupField: GroupField? = nil,
        path: String? = nil,
        kind: Kind
    ) {
        self.severity = severity
        self.area = area
        self.message = message
        self.fix = fix
        self.locale = locale
        self.deviceClassID = deviceClassID
        self.field = field
        self.productID = productID
        self.territory = territory
        self.productField = productField
        self.subscriptionGroup = subscriptionGroup
        self.groupField = groupField
        self.path = path
        self.kind = kind
    }
}

/// By hand, because `LocalizedStringResource` is not `Hashable`.
///
/// The identity is the rule and the thing it is about, which is what `id`
/// already holds. Two problems with the same `id` are the same problem however
/// the sentence is worded.
public extension Problem {
    static func == (lhs: Problem, rhs: Problem) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

public extension [Problem] {
    var errors: [Problem] { filter { $0.severity == .error } }
    var warnings: [Problem] { filter { $0.severity == .warning } }

    /// A project with no errors is the only kind that can be published.
    var blocksPublishing: Bool { errors.isEmpty == false }

    /// Errors first, then grouped so that one language's problems read together.
    var sortedForDisplay: [Problem] {
        sorted { lhs, rhs in
            if lhs.severity != rhs.severity { return lhs.severity < rhs.severity }
            if lhs.area != rhs.area {
                let order = Problem.Area.allCases
                return order.firstIndex(of: lhs.area)! < order.firstIndex(of: rhs.area)!
            }
            if lhs.subscriptionGroup != rhs.subscriptionGroup {
                return (lhs.subscriptionGroup ?? "") < (rhs.subscriptionGroup ?? "")
            }
            if lhs.productID != rhs.productID {
                return (lhs.productID ?? "") < (rhs.productID ?? "")
            }
            if lhs.locale != rhs.locale { return (lhs.locale ?? "") < (rhs.locale ?? "") }
            if lhs.territory != rhs.territory {
                return (lhs.territory ?? "") < (rhs.territory ?? "")
            }
            // By identity rather than by the sentence, so a project reads in the
            // same order whatever language the reader has.
            return lhs.id < rhs.id
        }
    }
}
