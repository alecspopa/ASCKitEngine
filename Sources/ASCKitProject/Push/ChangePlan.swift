import ASCKitAPI
import CryptoKit
import Foundation

/// Exactly what a push would do, worked out before anything is written.
///
/// Nothing writes to App Store Connect without making one of these first, and
/// both the command line tool and the app show it before they act.
public struct ChangePlan: Sendable {
    public let versionString: String
    public let versionState: AppVersionState?

    public let textChanges: [TextChange]

    /// Languages that are on disk and have no page on App Store Connect.
    ///
    /// A push writes nothing in them. ASCKit never makes a language on App
    /// Store Connect: a store page is what people read, and one that turns up
    /// because a file was on disk is a page nobody decided to publish. Make the
    /// language in App Store Connect and read again, or ignore it here.
    public let missingLocales: [String]

    public let screenshotPlans: [ScreenshotPlan]

    /// The app previews, which go only through the App Asset Library.
    public let previewPlans: [PreviewPlan]

    /// The product page header and search results art, which go only through
    /// the App Asset Library.
    public let creativePlans: [CreativePlan]

    /// Files in the folder of a language that shows the source language's
    /// screenshots or art. The tick wins, so they are not used, and a push of
    /// the images moves them to the Trash.
    public let unusedFiles: [UnusedFile]

    /// An in-app purchase's name or description, in one language.
    ///
    /// Sorted by product, then language, then field. The digest walks these in
    /// order, so two runs that find the same changes must list them the same
    /// way.
    public let productTextChanges: [ProductTextChange]

    /// A subscription group's display name or custom app name, in one
    /// language. Sorted by group, then language, then field.
    public let groupTextChanges: [GroupTextChange]

    /// What each in-app purchase would cost, everywhere.
    public let pricePlans: [PriceChange]

    /// In-app purchases that are in files and not on App Store Connect.
    ///
    /// A push never creates one. A product id is permanent and is compiled into
    /// the shipping app, and App Store Connect cannot delete a purchase at all,
    /// so making one from a file is a mistake nobody can undo.
    public let newProducts: [String]

    /// The products and groups whose words go into a new draft, because
    /// review is done with the version that holds them now.
    public let newDrafts: [String]

    /// Things a push cannot do in the version's current state.
    public let blocked: [Blocked]

    /// Languages left out on purpose, and why.
    public let skipped: [Skipped]

    public var isEmpty: Bool {
        textChanges.isEmpty
            && hasScreenshotChanges == false
            && productTextChanges.isEmpty
            && groupTextChanges.isEmpty
            && hasPriceChanges == false
    }

    /// Screenshots and app previews, which go out as one part of a push.
    public var hasScreenshotChanges: Bool {
        screenshotPlans.contains(where: \.changesAnything)
            || previewPlans.contains(where: \.changesAnything)
            || creativePlans.contains(where: \.changesAnything)
            || unusedFiles.isEmpty == false
    }

    /// The words of a purchase or of a subscription group. Both go out as one
    /// part of a push.
    public var hasProductTextChanges: Bool {
        productTextChanges.isEmpty == false || groupTextChanges.isEmpty == false
    }

    public var hasPriceChanges: Bool {
        pricePlans.contains { $0.changing.isEmpty == false }
    }

    /// Every country that would pay more, across every product.
    ///
    /// The money analogue of an image with no local file behind it: the thing a
    /// person has to agree to separately, because it is the one that cannot be
    /// taken back.
    public var priceRises: [PriceChange.Row] {
        pricePlans.flatMap(\.rises)
    }

    // MARK: - Counts

    /// How many languages the listing text would touch.
    public var changedTextLocales: Int {
        Set(textChanges.map(\.locale)).count
    }

    /// How many in-app purchases the words would touch.
    public var changedTextProducts: Int {
        Set(productTextChanges.map(\.productID)).count
    }

    /// How many subscription groups the words would touch.
    public var changedTextGroups: Int {
        Set(groupTextChanges.map(\.group)).count
    }

    public var changedPricedProducts: Int {
        pricePlans.count { $0.changing.isEmpty == false }
    }

    public var changedPriceRows: Int {
        pricePlans.reduce(0) { $0 + $1.changing.count }
    }

    public var changedScreenshotSets: Int {
        screenshotPlans.count(where: \.changesAnything)
    }

    public var imagesToAdd: Int {
        screenshotPlans.reduce(0) { total, item in
            guard case let .replace(_, adding) = item.action else { return total }
            return total + adding
        }
    }

    public var imagesToRemove: Int {
        screenshotPlans.reduce(0) { total, item in
            guard case let .replace(removing, _) = item.action else { return total }
            return total + removing
        }
    }

    /// Whether one part of a push has anything to do.
    public func changes(_ part: PublishPart) -> Bool {
        switch part {
        case .appInformation: textChanges.isEmpty == false
        case .purchases: hasProductTextChanges
        case .prices: hasPriceChanges
        case .screenshots: hasScreenshotChanges
        // An `ExperimentPlan` and a `CustomPagePlan` hold these.
        case .productPageOptimization, .customProductPages: false
        }
    }

    /// The three product members default to empty, so a caller that only cares
    /// about a version's listing reads exactly as it did before in-app
    /// purchases existed.
    public init(
        versionString: String,
        versionState: AppVersionState?,
        textChanges: [TextChange],
        missingLocales: [String],
        screenshotPlans: [ScreenshotPlan],
        previewPlans: [PreviewPlan] = [],
        creativePlans: [CreativePlan] = [],
        unusedFiles: [UnusedFile] = [],
        productTextChanges: [ProductTextChange] = [],
        groupTextChanges: [GroupTextChange] = [],
        pricePlans: [PriceChange] = [],
        newProducts: [String] = [],
        newDrafts: [String] = [],
        blocked: [Blocked],
        skipped: [Skipped]
    ) {
        self.versionString = versionString
        self.versionState = versionState
        self.textChanges = textChanges
        self.missingLocales = missingLocales
        self.screenshotPlans = screenshotPlans
        self.previewPlans = previewPlans
        self.creativePlans = creativePlans
        self.unusedFiles = unusedFiles
        self.productTextChanges = productTextChanges
        self.groupTextChanges = groupTextChanges
        self.pricePlans = pricePlans
        self.newProducts = newProducts
        self.newDrafts = newDrafts
        self.blocked = blocked
        self.skipped = skipped
    }

    // MARK: - Pieces

    public struct TextChange: Sendable, Hashable, Identifiable {
        public enum Action: String, Sendable {
            /// The language has no value for this field on App Store Connect.
            case add
            case change
        }

        public let locale: String
        public let field: MetadataField
        public let action: Action
        public let oldValue: String?
        public let newValue: String

        public var id: String { "\(locale)|\(field.rawValue)" }

        /// Name and subtitle are written to a different resource, and whether
        /// they can be written at all depends on a different state.
        public var isAppInfoField: Bool { field.isAppInfoField }
    }

    public struct ScreenshotPlan: Sendable, Identifiable {
        public enum Action: Sendable, Equatable {
            case unchanged
            /// The placements that go and the placements that come. Both are
            /// zero when only the order changes.
            case replace(removing: Int, adding: Int)
        }

        public let locale: String
        public let deviceClass: DeviceClass
        public let action: Action
        public let localFiles: [ScreenshotFile]

        /// How the slot compares in the App Asset Library.
        public let library: LibrarySlot

        public init(locale: String, deviceClass: DeviceClass, localFiles: [ScreenshotFile], library: LibrarySlot) {
            self.locale = locale
            self.deviceClass = deviceClass
            self.localFiles = localFiles
            self.library = library
            action = LibraryPlanner.action(for: library)
        }

        public var remoteCount: Int { library.current.count }

        public var id: String { "\(locale)|\(deviceClass.id)" }
        /// A change of order alone counts, though no file moves.
        public var changesAnything: Bool { library.isUnchanged == false }
    }

    /// The app previews of one device class in one language.
    public struct PreviewPlan: Sendable, Identifiable {
        public let locale: String
        public let deviceClass: DeviceClass
        public let action: ScreenshotPlan.Action
        public let localFiles: [PreviewFile]
        public let library: LibrarySlot

        public init(locale: String, deviceClass: DeviceClass, localFiles: [PreviewFile], library: LibrarySlot) {
            self.locale = locale
            self.deviceClass = deviceClass
            self.localFiles = localFiles
            self.library = library
            action = LibraryPlanner.action(for: library)
        }

        public var id: String { "\(locale)|\(deviceClass.id)|previews" }
        public var remoteCount: Int { library.current.count }

        /// A change of the poster frame alone counts, though no file moves.
        public var changesAnything: Bool { library.isUnchanged == false }
    }

    /// The same shape as a `TextChange`, deliberately, because it is the same
    /// idea about a different thing. Kept apart because the field enums differ:
    /// a product's name is 30 characters and a listing's is 30 with a floor of
    /// 2, and one type holding both would be right about neither.
    public struct ProductTextChange: Sendable, Hashable, Identifiable {
        public enum Action: String, Sendable {
            /// App Store Connect has no value for this field in this language.
            case add
            case change
        }

        public let productID: String
        public let locale: String
        public let field: ProductField
        public let action: Action
        public let oldValue: String?
        public let newValue: String

        public var id: String { "\(productID)|\(locale)|\(field.rawValue)" }
    }

    /// The same shape as a `ProductTextChange`, for a subscription group.
    public struct GroupTextChange: Sendable, Hashable, Identifiable {
        public let group: String
        public let locale: String
        public let field: GroupField
        public let action: ProductTextChange.Action
        public let oldValue: String?
        public let newValue: String

        public init(
            group: String,
            locale: String,
            field: GroupField,
            action: ProductTextChange.Action,
            oldValue: String?,
            newValue: String
        ) {
            self.group = group
            self.locale = locale
            self.field = field
            self.action = action
            self.oldValue = oldValue
            self.newValue = newValue
        }

        public var id: String { "\(group)|\(locale)|\(field.rawValue)" }
    }

    /// What one in-app purchase would cost in every country.
    ///
    /// Every country is here, including the ones that do not change. For a
    /// one-time purchase that is not a display choice: the write sends all of
    /// them, and a country left out of it goes back to Apple's equalized price.
    /// So the list is what would actually be sent.
    public struct PriceChange: Sendable, Identifiable {
        public let productID: String
        public let kind: Product.Kind
        public let baseTerritory: String
        public let baseAmount: Money
        public let curveID: String

        /// True for everything but an auto-renewable subscription.
        ///
        /// The two kinds are opposite. A one-time purchase has one schedule and
        /// writing it throws the old one away, so a country left out falls back
        /// to Apple's equalized price. A subscription is written country by
        /// country, and a country left out keeps what it has.
        public let replacesWholeSchedule: Bool

        /// Whether people who already subscribe keep what they pay. Nil for
        /// anything that is not a subscription.
        public let preserveCurrentPrice: Bool?

        public let rows: [Row]

        /// Countries left out of the write on purpose.
        public let skipped: [PriceResolver.Skipped]

        /// Countries with no price that ASCKit worked out, and that the file
        /// does not skip on purpose. While any is here, no price of this
        /// product goes out: App Store Connect would choose those prices
        /// itself.
        public internal(set) var unpriced: [String] = []

        public var id: String { productID }

        /// Which way one country's price moves.
        ///
        /// Beside `Row` rather than inside it, only so the type does not nest
        /// four deep.
        public enum Direction: String, Sendable {
            case up
            case down
            case same
            /// The store charges nothing here yet.
            case new
        }

        /// Which of a subscription's two prices a row is.
        ///
        /// A yearly subscription sold with instalments has both in every
        /// country: what it costs bought outright, and what one month costs.
        /// Everything else has only the first.
        public enum PlanType: String, Sendable {
            case upfront = "UPFRONT"
            /// One instalment of a yearly subscription paid monthly.
            case monthly = "MONTHLY"

            public var displayName: String {
                switch self {
                case .upfront: String(localized: "the year", bundle: .module)
                case .monthly: String(localized: "one month", bundle: .module)
                }
            }
        }

        public struct Row: Sendable, Hashable, Identifiable {
            public let territory: String

            public let planType: PlanType
            public let currency: String?
            public let pricePointID: String
            public let oldAmount: Money?
            public let newAmount: Money
            public let direction: Direction
            public let source: PriceResolver.Source

            /// How much rounding added on top of what the curve asked for.
            public let roundedUpBy: Money

            public var id: String { "\(territory)|\(planType.rawValue)" }

            /// The currency to show a price in. `currency` stays nil to keep
            /// the digest the same, so the territory table gives it.
            public var shownCurrency: String? {
                currency ?? Territory.named(territory)?.currency
            }
        }

        public var changing: [Row] { rows.filter { $0.direction != .same } }
        public var rises: [Row] { rows.filter { $0.direction == .up } }
        public var falls: [Row] { rows.filter { $0.direction == .down } }
        public var unchanged: [Row] { rows.filter { $0.direction == .same } }
    }

    public struct Blocked: Sendable, Hashable {
        /// What refuses the change, coarsely, so a one-line summary can name it
        /// without repeating the whole reason.
        public enum Cause: Sendable, Hashable {
            /// The state of the version itself, which no file can change.
            case versionStatus

            /// One in-app purchase: missing, in a state that refuses edits, or
            /// with no prices read yet.
            case product
        }

        public let reason: LocalizedStringResource
        public let affects: LocalizedStringResource
        public let cause: Cause

        /// The parts of a push this holds up. A set, because an in-app purchase
        /// in review refuses its words and its prices both.
        public let parts: PublishParts

        public init(
            reason: LocalizedStringResource,
            affects: LocalizedStringResource,
            cause: Cause,
            parts: PublishParts
        ) {
            self.reason = reason
            self.affects = affects
            self.cause = cause
            self.parts = parts
        }

        /// Written by hand over the English, because a
        /// `LocalizedStringResource` is not `Hashable` and because a plan has
        /// to compare the same either side of a change of language.
        public static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.cause == rhs.cause
                && lhs.parts == rhs.parts
                && lhs.reason.english == rhs.reason.english
                && lhs.affects.english == rhs.affects.english
        }

        public func hash(into hasher: inout Hasher) {
            hasher.combine(cause)
            hasher.combine(parts)
            hasher.combine(reason.english)
            hasher.combine(affects.english)
        }
    }

    /// What holds up one part, in the order the plan found it.
    public func blocked(_ part: PublishPart) -> [Blocked] {
        blocked.filter { $0.parts.contains(part) }
    }

    /// A file of a language that shows the source language's screenshots or
    /// art in its place.
    public struct UnusedFile: Sendable, Hashable {
        public enum Slot: Sendable, Hashable {
            case screenshots(DeviceClass)
            case previews(DeviceClass)
            case creative(CreativeRole)
        }

        public let locale: String
        public let slot: Slot
        public let url: URL
        public let fileName: String

        public init(locale: String, slot: Slot, url: URL, fileName: String) {
            self.locale = locale
            self.slot = slot
            self.url = url
            self.fileName = fileName
        }

        /// A device class id, the same with `/previews`, or a role such as
        /// `header`.
        public var slotID: String {
            switch slot {
            case let .screenshots(deviceClass): deviceClass.id
            case let .previews(deviceClass): "\(deviceClass.id)/previews"
            case let .creative(role): role.rawValue
            }
        }
    }

    public struct Skipped: Sendable, Hashable {
        public let locale: String
        public let reason: LocalizedStringResource

        public init(locale: String, reason: LocalizedStringResource) {
            self.locale = locale
            self.reason = reason
        }

        /// The same reason `Blocked` writes its own.
        public static func == (lhs: Self, rhs: Self) -> Bool {
            lhs.locale == rhs.locale && lhs.reason.english == rhs.reason.english
        }

        public func hash(into hasher: inout Hasher) {
            hasher.combine(locale)
            hasher.combine(reason.english)
        }
    }
}

public extension ChangePlan {
    /// A digest of everything this plan would do, at full length.
    ///
    /// This is how a caller tells that the plan somebody read a minute ago is
    /// still the plan. App Store Connect changes without asking, so an upload
    /// reads it again first, and writing what came back the second time would
    /// be writing something nobody agreed to.
    ///
    /// Values go in whole, not shortened the way they are shortened on screen,
    /// so a change past the end of a printed line still moves the digest.
    var digest: String {
        digest(includingPricePointIDs: true)
    }

    /// The same, without Apple's identifier for each price point.
    ///
    /// This is what a person agreed to: the money, and where each number came
    /// from. The identifier is Apple's own bookkeeping, and it is left out on
    /// purpose.
    ///
    /// Leaving it in refuses pushes it cannot protect. A push writes the plan
    /// from the *second* read, not the one on screen, so an identifier Apple
    /// regenerated between the two goes out correctly either way. Comparing
    /// them can only stop a push whose every price is the same.
    ///
    /// `digest` keeps the identifiers, because a record of what a plan held is
    /// a different thing from what somebody said yes to.
    var agreementDigest: String {
        digest(includingPricePointIDs: false)
    }

    private func digest(includingPricePointIDs: Bool) -> String {
        var hasher = SHA256()
        func feed(_ parts: String...) {
            for part in parts {
                hasher.update(data: Data(part.utf8))
                hasher.update(data: Data([0]))
            }
        }

        feed(versionString, versionState?.rawValue ?? "")
        feed(missingLocales.joined(separator: ","))

        for change in textChanges {
            feed(
                change.locale, change.field.rawValue, change.action.rawValue,
                change.oldValue ?? "", change.newValue
            )
        }

        // The bytes of an image are not read here. A set that gained, lost or
        // moved a file changes its action, and a file edited in place changes
        // its size, so the plan moves either way.
        for plan in screenshotPlans {
            feed(plan.locale, plan.deviceClass.id, plan.action.digestKey, "\(plan.remoteCount)")
            for file in plan.localFiles {
                feed(file.fileName, "\(file.byteCount)")
            }
        }

        // Fed only when there is one, so a plan with no previews keeps the
        // digest it had before previews.
        for plan in previewPlans {
            feed(plan.id, plan.action.digestKey, "\(plan.remoteCount)")
            for file in plan.localFiles {
                feed(file.fileName, "\(file.byteCount)", file.posterFrame ?? "")
            }
        }
        for plan in creativePlans {
            feed(plan.id, plan.action.digestKey, plan.file?.fileName ?? "", "\(plan.file?.byteCount ?? 0)")
        }

        // Fed only when there is one, so a plan with none keeps its digest.
        for file in unusedFiles {
            feed("unused", file.locale, file.slotID, file.fileName)
        }

        for change in productTextChanges {
            feed(
                change.productID, change.locale, change.field.rawValue,
                change.action.rawValue, change.oldValue ?? "", change.newValue
            )
        }

        // Fed only when there is one, so a plan with no group words keeps the
        // digest it had before groups had words.
        for change in groupTextChanges {
            feed(
                "group", change.group, change.locale, change.field.rawValue,
                change.action.rawValue, change.oldValue ?? "", change.newValue
            )
        }

        // Every country goes in, not only the ones that change. A one-time
        // purchase's write sends all of them, so all of them are what somebody
        // agreed to. Where the number came from goes in too, so that a row
        // moving from the curve to an override with the same amount still
        // counts as a change.
        //
        // The price point id goes in only for `digest`. See `agreementDigest`
        // for why the check a push makes leaves it out.
        feed(newProducts.joined(separator: ","))
        for plan in pricePlans {
            feed(
                plan.productID, plan.kind.rawValue, plan.curveID,
                plan.baseTerritory, plan.baseAmount.description,
                plan.replacesWholeSchedule ? "replace" : "merge",
                plan.preserveCurrentPrice.map { $0 ? "preserve" : "raise" } ?? ""
            )
            for row in plan.rows {
                feed(
                    row.territory, row.planType.rawValue,
                    row.currency ?? "",
                    includingPricePointIDs ? row.pricePointID : "",
                    row.oldAmount?.description ?? "", row.newAmount.description,
                    row.direction.rawValue, row.source.digestKey
                )
            }
            for left in plan.skipped {
                feed(left.territory, left.reason.english)
            }
        }

        // The English, not the reader's own words. A digest is compared with
        // one written earlier, and a change of language must not look like a
        // change of plan.
        for item in blocked {
            feed(item.reason.english, item.affects.english)
        }
        for item in skipped {
            feed(item.locale, item.reason.english)
        }

        let hex = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        return "sha256:\(hex)"
    }
}

private extension ChangePlan.ScreenshotPlan.Action {
    /// Written out rather than interpolated, so the digest does not depend on
    /// how Swift happens to describe an enum with values in it.
    var digestKey: String {
        switch self {
        case .unchanged: "unchanged"
        case let .replace(removing, adding): "replace-\(removing)-\(adding)"
        }
    }
}
