import Foundation

/// What one push did, written into the project's history folder.
///
/// A push says what happened once, on a terminal nobody keeps. The receipt is
/// the record: what went, what App Store Connect refused, and the reason it
/// gave. A field refused today is usually refused for a reason that changes
/// later, and without this there is nothing to look back at.
public struct PushReceipt: Codable, Sendable, Hashable {
    public enum Kind: String, Codable, Sendable {
        case text
        case images
        /// The images of a draft Product Page Optimization test.
        case experimentImages
        /// An in-app purchase's names and descriptions.
        case productText
        /// What in-app purchases cost, country by country.
        case prices
        /// The deep links, promotional text and keywords of the custom
        /// product pages.
        case customPageText
        /// The images of the custom product pages.
        case customPageImages
    }

    public let pushedAt: Date
    public let kind: Kind

    /// Nil for a push that has nothing to do with a version. An in-app purchase
    /// hangs off the app, so its price and its words belong to no release.
    public let version: String?

    public let appVersionState: String?

    public let written: [String]
    public let refused: [RefusedField]
    public let failed: [FailedLocale]

    /// What each country was charged before and after.
    ///
    /// Optional, so every receipt already on disk still reads. This is the
    /// audit trail for a change that moves real money, and it is the most
    /// important thing this file holds.
    public let prices: [PriceWritten]?

    /// Which version of its words each product was written into.
    ///
    /// Optional, so every receipt already on disk still reads. A version is
    /// what App Review looks at, so the one a push wrote to is what somebody
    /// looks for in App Store Connect afterwards.
    public let productVersions: [ProductVersionWritten]?

    /// The asset ids and placement ids of each slot an image push wrote.
    ///
    /// Optional, so every receipt already on disk still reads. A placement id
    /// is what App Store Connect names in an error about a slot, and an asset
    /// id is what the record and `asckit library` name.
    public let library: [LibrarySlotWritten]?

    public struct LibrarySlotWritten: Codable, Sendable, Hashable {
        /// The language and the device class or role, such as
        /// `en-US|iphone-6.9`.
        public let slot: String
        public let assetIDs: [String]
        public let placementIDs: [String]
        public let removedPlacementIDs: [String]
        public let uploadedAssetIDs: [String]

        public init(
            slot: String,
            assetIDs: [String],
            placementIDs: [String],
            removedPlacementIDs: [String],
            uploadedAssetIDs: [String]
        ) {
            self.slot = slot
            self.assetIDs = assetIDs
            self.placementIDs = placementIDs
            self.removedPlacementIDs = removedPlacementIDs
            self.uploadedAssetIDs = uploadedAssetIDs
        }
    }

    public struct ProductVersionWritten: Codable, Sendable, Hashable {
        /// The product id, or a subscription group's reference name.
        public let productID: String

        /// Apple's opaque id for the version.
        public let versionID: String

        /// Apple's counter, 1 for the first.
        public let version: Int?

        public init(productID: String, versionID: String, version: Int?) {
            self.productID = productID
            self.versionID = versionID
            self.version = version
        }
    }

    public struct PriceWritten: Codable, Sendable, Hashable {
        public let productID: String
        public let territory: String

        /// `UPFRONT` or `MONTHLY`. A yearly subscription sold with a 12-month
        /// commitment has both, and the record has to say which one moved.
        public let planType: String?
        public let currency: String?

        /// What the country paid before. Nil when the store charged nothing
        /// there yet.
        public let from: String?

        public let to: String

        /// Apple regenerates these, so the one that was actually written is
        /// worth keeping.
        public let pricePointID: String

        /// Whether people who already subscribe kept what they pay. Nil for
        /// anything that is not a subscription.
        public let preservedCurrentPrice: Bool?

        public init(
            productID: String,
            territory: String,
            planType: String? = nil,
            currency: String?,
            from: String?,
            to: String,
            pricePointID: String,
            preservedCurrentPrice: Bool?
        ) {
            self.productID = productID
            self.territory = territory
            self.planType = planType
            self.currency = currency
            self.from = from
            self.to = to
            self.pricePointID = pricePointID
            self.preservedCurrentPrice = preservedCurrentPrice
        }
    }

    public struct RefusedField: Codable, Sendable, Hashable {
        public let locale: String
        public let field: String

        /// What App Store Connect said, in its own words.
        public let reason: String

        public init(locale: String, field: String, reason: String) {
            self.locale = locale
            self.field = field
            self.reason = reason
        }
    }

    public struct FailedLocale: Codable, Sendable, Hashable {
        public let locale: String
        public let reason: String

        public init(locale: String, reason: String) {
            self.locale = locale
            self.reason = reason
        }
    }

    public init(
        pushedAt: Date,
        kind: Kind,
        version: String?,
        appVersionState: String?,
        written: [String],
        refused: [RefusedField],
        failed: [FailedLocale],
        prices: [PriceWritten]? = nil,
        productVersions: [ProductVersionWritten]? = nil,
        library: [LibrarySlotWritten]? = nil
    ) {
        self.pushedAt = pushedAt
        self.kind = kind
        self.version = version
        self.appVersionState = appVersionState
        self.written = written
        self.refused = refused
        self.failed = failed
        self.prices = prices
        self.productVersions = productVersions
        self.library = library
    }

    public var isCompleteSuccess: Bool { refused.isEmpty && failed.isEmpty }
}

/// Where receipts are kept, and how they are named.
public enum PushHistory {
    /// Sorts by name, because the name starts with the time.
    public static func fileName(for receipt: PushReceipt) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate, .withTime, .withColonSeparatorInTime]
        let stamp = formatter.string(from: receipt.pushedAt)
            .replacingOccurrences(of: ":", with: "-")
        // A push with no version is an in-app purchase, which belongs to no
        // release, so the slot the version fills says what it was instead.
        return "\(stamp)-\(receipt.version ?? "products")-\(receipt.kind.rawValue).json"
    }

    @discardableResult
    public static func write(_ receipt: PushReceipt, to project: Project) throws -> URL {
        try FileManager.default.createDirectory(
            at: project.historyURL,
            withIntermediateDirectories: true
        )

        let url = project.historyURL.appending(path: fileName(for: receipt))
        try ProjectJSON.write(receipt, to: url, datesAsISO8601: true)
        return url
    }

    /// Newest first.
    public static func read(from project: Project) -> [PushReceipt] {
        let decoder = ProjectJSON.decoder(datesAsISO8601: true)

        return DirectoryListing.files(in: project.historyURL)
            .filter { $0.pathExtension.lowercased() == "json" }
            .compactMap { try? decoder.decode(PushReceipt.self, from: try Data(contentsOf: $0)) }
            .sorted { $0.pushedAt > $1.pushedAt }
    }
}

public extension PushReceipt {
    /// Built from what the text pusher reported.
    static func forText(
        _ result: TextPusher.Result,
        version: String,
        appVersionState: String?,
        at date: Date
    ) -> PushReceipt {
        PushReceipt(
            pushedAt: date,
            kind: .text,
            version: version,
            appVersionState: appVersionState,
            written: result.written,
            refused: result.refused.map {
                RefusedField(locale: $0.locale, field: $0.field.rawValue, reason: $0.reason)
            },
            failed: result.failed.map { FailedLocale(locale: $0.locale, reason: $0.message) }
        )
    }

    /// Built from what the product pusher reported.
    ///
    /// `version` stays nil. That field holds a listing's version string and
    /// names the receipt file, and one push touches many products with a
    /// version number each. Those go in `productVersions`.
    static func forProductText(_ result: ProductPusher.TextResult, at date: Date) -> PushReceipt {
        PushReceipt(
            pushedAt: date,
            kind: .productText,
            version: nil,
            appVersionState: nil,
            written: result.written,
            refused: [],
            failed: result.failed.map {
                FailedLocale(locale: failureName(of: $0), reason: $0.reason)
            },
            productVersions: result.drafts.map {
                ProductVersionWritten(
                    productID: $0.productID, versionID: $0.versionID, version: $0.number
                )
            }
        )
    }

    static func forPrices(_ result: ProductPusher.PriceResult, at date: Date) -> PushReceipt {
        PushReceipt(
            pushedAt: date,
            kind: .prices,
            version: nil,
            appVersionState: nil,
            written: result.written.map { "\($0.productID) \($0.territory) \($0.planType) \($0.to)" },
            refused: [],
            failed: result.failed.map {
                FailedLocale(locale: failureName(of: $0), reason: $0.reason)
            },
            prices: result.written.map {
                PriceWritten(
                    productID: $0.productID,
                    territory: $0.territory,
                    planType: $0.planType,
                    currency: $0.currency,
                    from: $0.from,
                    to: $0.to,
                    pricePointID: $0.pricePointID,
                    preservedCurrentPrice: $0.preservedCurrentPrice
                )
            }
        )
    }

    /// The product and the country, or the product on its own when the whole of
    /// it failed.
    private static func failureName(of failure: ProductPusher.Failure) -> String {
        failure.what.isEmpty
            ? failure.productID
            : "\(failure.productID) \(failure.what)"
    }

    static func forCustomPageText(_ result: CustomPageTextPusher.Result, at date: Date) -> PushReceipt {
        PushReceipt(
            pushedAt: date,
            kind: .customPageText,
            version: nil,
            appVersionState: nil,
            written: result.written,
            refused: [],
            failed: result.failed.map { FailedLocale(locale: $0.label, reason: $0.message) }
        )
    }

    static func forExperimentImages(
        _ result: ScreenshotPusher.Result,
        kind: Kind = .experimentImages,
        at date: Date
    ) -> PushReceipt {
        PushReceipt(
            pushedAt: date,
            kind: kind,
            version: nil,
            appVersionState: nil,
            written: result.uploaded,
            refused: [],
            failed: result.failed.map {
                FailedLocale(locale: "\($0.locale) \($0.deviceClassID)", reason: $0.message)
            },
            library: librarySlots(of: result)
        )
    }

    static func forImages(
        _ result: ScreenshotPusher.Result,
        version: String,
        appVersionState: String?,
        at date: Date
    ) -> PushReceipt {
        PushReceipt(
            pushedAt: date,
            kind: .images,
            version: version,
            appVersionState: appVersionState,
            written: result.uploaded,
            refused: [],
            failed: result.failed.map {
                FailedLocale(
                    locale: "\($0.locale) \($0.deviceClassID)",
                    reason: $0.message
                )
            },
            library: librarySlots(of: result)
        )
    }

    private static func librarySlots(of result: ScreenshotPusher.Result) -> [LibrarySlotWritten] {
        result.slots.map {
            LibrarySlotWritten(
                slot: $0.slot,
                assetIDs: $0.assetIDs,
                placementIDs: $0.placementIDs,
                removedPlacementIDs: $0.removedPlacementIDs,
                uploadedAssetIDs: $0.uploadedAssetIDs
            )
        }
    }
}
