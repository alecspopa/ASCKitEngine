import ASCKitAPI
import Foundation

/// One push, from reading App Store Connect to writing down what happened.
///
/// The app and the command line tool both go through this. Where the key comes
/// from and how a person is asked differ between them. Nothing else may: the
/// same read, the same plan, the same write, and the same record filed
/// afterwards.
///
/// Nothing outside this file can write a listing. `TextPusher` and
/// `ScreenshotPusher` are reachable only from inside the package, so a caller
/// cannot push and forget the record of it.
public struct PushSession: Sendable {
    public let project: Project
    let client: ASCClient

    public init(project: Project, client: ASCClient) {
        self.project = project
        self.client = client
    }

    // MARK: - Reading

    /// What App Store Connect holds, and what a push would change.
    public struct Reading: Sendable {
        public let listing: RemoteListing

        /// Whether the version App Store Connect is on has a folder here.
        public let drift: VersionDrift.Outcome

        /// What is on disk for that version, and what a push would change.
        ///
        /// Both are nil when there is no folder for the version App Store
        /// Connect is on, because nothing can be planned against a folder that
        /// is not there.
        public let content: VersionContent?
        public let changes: ChangePlan?

        /// The in-app purchases on disk, and the ones App Store Connect holds.
        ///
        /// Filled in whatever the version drift says, because a product is not
        /// tied to a version. Nil only when nobody asked for them.
        public let products: ProductCatalog?
        public let remoteProducts: RemoteProducts?

        /// Anything the price reader said while working the plan out.
        public let priceProblems: [Problem]

        /// Where each priced product's ladder came from, keyed by product id.
        /// Empty when nobody asked for prices.
        public let priceOrigins: [String: PriceLadderCache.Origin]

        /// What each country pays today, keyed by product then by country.
        ///
        /// Every product App Store Connect holds a file for, priced by this
        /// project or not. Empty when nobody asked for prices.
        public let currentPrices: [String: [String: Money]]

        /// What one monthly instalment costs today, keyed by product then by
        /// country.
        ///
        /// Only a yearly subscription sold in instalments has these, and only
        /// in the countries that offer them. Empty when nobody asked for prices.
        public let currentMonthlyPrices: [String: [String: Money]]

        /// The app's library and this project's record of it. Nil when the
        /// app has no library, and then screenshots go to the old sets.
        public var library: LibraryState?

        /// The version App Store Connect moved to, when this project has no
        /// folder for it. Nil when the two agree.
        public var versionToCreate: String? { drift.versionToCreate }
    }

    /// Reads App Store Connect and works out what a push would change.
    ///
    /// Writes nothing, on either side.
    ///
    /// A version App Store Connect has and this project has no folder for is
    /// reported rather than thrown. It is not a broken project. It is the first
    /// minute of a new release, and what it needs is a folder.
    /// - Parameters:
    ///   - includeProducts: Whether to read the in-app purchases as well.
    ///   - includeLiveTexts: Whether to read the words of the version on sale,
    ///     which say what this version changed.
    ///   - prices: Where to get every priced product's ladder. A ladder is
    ///     thousands of rows per product, so `.notRead` is the default and
    ///     everything else is somebody about to look at a price or write one.
    public func read(
        version: String? = nil,
        includeScreenshots: Bool = true,
        includeProducts: Bool = true,
        includeLiveTexts: Bool = false,
        prices: PriceSource = .notRead
    ) async throws -> Reading {
        let listing = try await client.listing(
            bundleID: project.config.bundleID,
            versionString: version,
            platform: project.config.resolvedPlatform,
            includeScreenshots: includeScreenshots,
            includeLiveTexts: includeLiveTexts
        )

        let drift = try VersionDrift.compare(listing: listing, project: project)
        let library = includeScreenshots ? try await readLibrary(appID: listing.appID, listing: listing) : nil
        if includeScreenshots, library == nil { throw LibraryReadError.noLibrary }

        // Products come first, and come whatever the drift says. A purchase is
        // not tied to a version, so a version folder that is not there yet must
        // not stop somebody reading or changing a price.
        let onDisk = includeProducts ? ProductStore.load(in: project) : nil
        let onStore = includeProducts
            ? try await client.products(bundleID: project.config.bundleID)
            : nil

        var product: ProductPlanner.Outcome?
        var origins: [String: PriceLadderCache.Origin] = [:]
        var currentPrices: [String: [String: Money]] = [:]
        var currentMonthlyPrices: [String: [String: Money]] = [:]
        if let onDisk, let onStore {
            let read = prices.wantsPrices
                ? try await readPrices(for: onDisk, on: onStore, source: prices)
                : (prices: ProductPlanner.Prices(), origins: [:])
            origins = read.origins
            currentPrices = read.prices.current
            currentMonthlyPrices = read.prices.currentMonthly

            product = ProductPlanner.plan(
                local: onDisk,
                config: project.config,
                remote: onStore,
                prices: read.prices
            )
        }

        let content = drift.versionToCreate == nil
            ? try ContentStore.load(version: listing.versionString, in: project)
            : nil

        let listingPlan = content.map {
            Planner.plan(local: $0, config: project.config, remote: listing, record: library?.record ?? AssetRecord())
        }

        return Reading(
            listing: listing,
            drift: drift,
            content: content,
            changes: merge(listingPlan, with: product, listing: listing),
            products: onDisk,
            remoteProducts: onStore,
            priceProblems: product?.problems ?? [],
            priceOrigins: origins,
            currentPrices: currentPrices,
            currentMonthlyPrices: currentMonthlyPrices,
            library: library
        )
    }

    /// One plan out of two halves.
    ///
    /// Nil only when there is nothing to say at all: no version folder and no
    /// products. A caller reading `changes` for the listing still sees empty
    /// text and screenshot lists when the folder is missing, which is what it
    /// saw before.
    private func merge(
        _ listingPlan: ChangePlan?,
        with product: ProductPlanner.Outcome?,
        listing: RemoteListing
    ) -> ChangePlan? {
        guard listingPlan != nil || product != nil else { return nil }

        return ChangePlan(
            versionString: listing.versionString,
            versionState: listing.versionState,
            textChanges: listingPlan?.textChanges ?? [],
            missingLocales: listingPlan?.missingLocales ?? [],
            screenshotPlans: listingPlan?.screenshotPlans ?? [],
            previewPlans: listingPlan?.previewPlans ?? [],
            creativePlans: listingPlan?.creativePlans ?? [],
            unusedFiles: listingPlan?.unusedFiles ?? [],
            productTextChanges: product?.textChanges ?? [],
            groupTextChanges: product?.groupTextChanges ?? [],
            pricePlans: product?.pricePlans ?? [],
            newProducts: product?.newProducts ?? [],
            newDrafts: product?.newDrafts ?? [],
            blocked: (listingPlan?.blocked ?? []) + (product?.blocked ?? []),
            skipped: (listingPlan?.skipped ?? []) + (product?.skipped ?? [])
        )
    }

    /// Every priced product's ladder, its anchors, and what it costs today.
    ///
    /// One product at a time rather than all at once. A ladder is several
    /// requests on its own, and running twenty products' worth together is how
    /// a rate limit is met.
    ///
    /// What each country pays today is read from App Store Connect for every
    /// product, whatever `source` says. It is one request for a subscription
    /// and three for a purchase, and it is the number a plan calls "old", so a
    /// kept copy would report a rise as no change and the rule guarding a rise
    /// would stop working without saying so.
    private func readPrices(
        for onDisk: ProductCatalog,
        on onStore: RemoteProducts,
        source: PriceSource
    ) async throws -> (prices: ProductPlanner.Prices, origins: [String: PriceLadderCache.Origin]) {
        var anchors: [String: [String: Money]] = [:]
        var ladders: [String: [String: [PricePoint]]] = [:]
        var current: [String: [String: Money]] = [:]
        var currentMonthly: [String: [String: Money]] = [:]
        var origins: [String: PriceLadderCache.Origin] = [:]

        let byProductID = onStore.byProductID
        for product in onDisk.sorted {
            guard let match = byProductID[product.productID] else { continue }

            // Today's price, whether or not this project prices the product.
            // A product with no price plan still sells for something, and that
            // number is where somebody pricing it starts.
            let today = try await client.currentPrices(for: match)
            current[product.productID] = today.current.compactMapValues(Money.init(string:))
            currentMonthly[product.productID] = today.currentMonthly
                .compactMapValues(Money.init(string:))

            // The ladder is the expensive half, and only a priced product needs
            // one: nothing works out a price for a product with no plan.
            guard let plan = product.price else { continue }

            let rungs = try await ladder(
                for: plan, on: match, productID: product.productID, source: source
            )
            anchors[product.productID] = rungs.anchors
            ladders[product.productID] = rungs.rungs
            origins[product.productID] = rungs.origin

            keep(
                productID: product.productID,
                plan: plan,
                match: match,
                ladder: rungs,
                today: (current[product.productID] ?? [:],
                        currentMonthly[product.productID] ?? [:])
            )
        }

        return (
            ProductPlanner.Prices(
                anchors: anchors,
                ladders: ladders,
                current: current,
                currentMonthly: currentMonthly
            ),
            origins
        )
    }

    /// One product's ladder, its anchors, and where the two came from.
    struct Ladder {
        let anchors: [String: Money]
        let rungs: [String: [PricePoint]]
        let origin: PriceLadderCache.Origin
    }

    /// One product's ladder and anchors, off the disk when the disk still holds
    /// the right ones, and off App Store Connect otherwise.
    ///
    /// The decision is per product, not per run. A person who changed one base
    /// price pays for that one product and reads the rest off a file.
    func ladder(
        for plan: Product.PricePlan,
        on match: RemoteProduct,
        productID: String,
        source: PriceSource
    ) async throws -> Ladder {
        let identity = RemoteProductIdentity(
            id: match.id, isAutoRenewable: match.isAutoRenewable
        )

        if source == .cached,
           let kept = PriceLadderStore.load(productID: productID, in: project),
           kept.isUsable(for: plan, on: identity, covering: Territory.allIdentifiers) {
            return Ladder(
                anchors: kept.anchors,
                rungs: kept.everyLadder,
                origin: .cache(readOn: kept.readOn)
            )
        }

        let read = try await client.ladderAndAnchors(
            for: match,
            baseTerritory: plan.baseTerritory,
            baseAmount: plan.baseAmount.description,
            territories: Territory.allIdentifiers
        )

        // No currency and no proceeds. A kept ladder cannot hold either, and a
        // plan built from one has to match a plan built from this row for row
        // or the digest a push compares is a digest of something else.
        let points = read.ladders.mapValues { rungs in
            rungs.compactMap { rung in
                Money(string: rung.customerPrice).map {
                    PricePoint(id: rung.id, territory: rung.territory, customerPrice: $0)
                }
            }
        }
        return Ladder(
            anchors: read.anchors.compactMapValues(Money.init(string:)),
            rungs: points,
            origin: .network
        )
    }

    /// Keeps what Apple answered, in two files.
    ///
    /// The ladder, with Apple's identifiers, so a window can plan a push
    /// without asking again. And the smaller identifier-free view, so a caller
    /// can price a product with no network and no key.
    ///
    /// A failure here is swallowed. These are caches, the numbers are already
    /// in hand, and a full disk must not stop a push that was going to work.
    ///
    /// A ladder that came off the disk is not written back to it. Nothing about
    /// it changed. What each country pays did, so the small file is written
    /// either way.
    func keep(
        productID: String,
        plan: Product.PricePlan,
        match: RemoteProduct,
        ladder: Ladder,
        today: (current: [String: Money], monthly: [String: Money])
    ) {
        let anchors = ladder.anchors
        let ladders = ladder.rungs

        if ladder.origin == .network {
            try? PriceLadderStore.save(
                PriceLadderCache(
                    productID: productID,
                    remoteProductID: match.id,
                    isAutoRenewable: match.isAutoRenewable,
                    readOn: PriceLadderCache.today(),
                    baseTerritory: plan.baseTerritory,
                    baseAmount: plan.baseAmount,
                    anchors: anchors,
                    ladders: ladders.mapValues { rungs in
                        PriceLadderCache.Steps(
                            ids: rungs.map(\.id), prices: rungs.map(\.customerPrice)
                        )
                    },
                    readForTerritories: Territory.allIdentifiers
                ),
                in: project
            )
        }

        // The prices, not the price points. This is the file an AI reads, and
        // an identifier is the thing a write needs, so the only ones kept are
        // the handful the product file names by hand.
        let named = Set(plan.overrides.values.compactMap(\.pricePoint))

        try? PricePointStore.save(
            PricePointCache(
                productID: productID,
                readOn: PricePointCache.today(),
                baseTerritory: plan.baseTerritory,
                baseAmount: plan.baseAmount,
                anchors: anchors,
                current: today.current,
                currentMonthly: today.monthly,
                ladders: ladders.mapValues { $0.map(\.customerPrice) },
                namedPoints: ladders.values.flatMap(\.self).filter { named.contains($0.id) }
            ),
            in: project
        )
    }

    // MARK: - Writing

    /// What a push did, and where the record of it went.
    public struct Outcome<Result: Sendable>: Sendable {
        public let result: Result

        /// Where the record of this push went. Nil when it could not be
        /// written.
        public let receiptURL: URL?

        /// Why the record could not be written. A push that worked must not
        /// read as failed because the note about it could not be filed.
        public let receiptFailure: String?
    }

    /// Writes the listing text, then files the record of it.
    @discardableResult
    public func pushText(
        _ reading: Reading,
        at date: Date = .now,
        progress: (@Sendable (String) -> Void)? = nil
    ) async throws -> Outcome<TextPusher.Result> {
        let planned = try planned(in: reading)

        let result = await TextPusher(client: client).push(
            planned.changes,
            to: reading.listing,
            localInformation: planned.content.appInformation,
            progress: progress
        )
        return file(
            PushReceipt.forText(
                result,
                version: reading.listing.versionString,
                appVersionState: reading.listing.versionState?.rawValue,
                at: date
            ),
            for: result
        )
    }

    /// Uploads the screenshots, then files the record of it.
    @discardableResult
    public func pushImages(
        _ reading: Reading,
        at date: Date = .now,
        progress: (@Sendable (ScreenshotPusher.Step) -> Void)? = nil
    ) async throws -> Outcome<ScreenshotPusher.Result> {
        let planned = try planned(in: reading)

        guard let library = reading.library else { throw LibraryReadError.notRead }
        var result = await pushToLibrary(
            Self.targets(in: planned.changes, listing: reading.listing),
            library: library,
            at: date,
            progress: progress
        )
        Self.trash(planned.changes.unusedFiles, into: &result)
        return file(
            PushReceipt.forImages(
                result,
                version: reading.listing.versionString,
                appVersionState: reading.listing.versionState?.rawValue,
                at: date
            ),
            for: result
        )
    }

    // MARK: - Product Page Optimization

    /// The draft tests on App Store Connect, the images on disk for them, and
    /// what a push would change.
    public struct ExperimentReading: Sendable {
        public let remote: RemoteExperiments
        public let content: ExperimentContent
        public let plan: ExperimentPlan

        /// The empty folders this read made, one for each language of each
        /// treatment, so images can be dropped straight in.
        public let madeFolders: [URL]

        /// The app's library and the record of it.
        public var library: LibraryState
    }

    /// Reads the draft tests and makes their folders.
    ///
    /// Writes nothing to App Store Connect. Makes only empty folders on disk,
    /// and only when `makeFolders` is true.
    public func readExperiments(makeFolders: Bool = true) async throws -> ExperimentReading {
        let remote = try await client.draftExperiments(bundleID: project.config.bundleID)
        guard let library = try await readLibrary(appID: remote.appID, listing: nil) else {
            throw LibraryReadError.noLibrary
        }
        let made = makeFolders ? try ExperimentFolders.scaffold(remote, in: project) : []

        // A cache, so a failure here must not stop the read.
        try? ExperimentSnapshotStore.save(ExperimentSnapshot(remote), in: project)
        let content = ExperimentContentStore.load(in: project)
        return ExperimentReading(
            remote: remote,
            content: content,
            plan: ExperimentPlanner.plan(local: content, config: project.config, remote: remote, record: library.record),
            madeFolders: made,
            library: library
        )
    }

    /// Uploads the images of the draft tests, then files the record of it.
    @discardableResult
    public func pushExperimentImages(
        _ reading: ExperimentReading,
        at date: Date = .now,
        progress: (@Sendable (ScreenshotPusher.Step) -> Void)? = nil
    ) async -> Outcome<ScreenshotPusher.Result> {
        let result = await pushToLibrary(
            Self.targets(in: reading.plan), library: reading.library, at: date, progress: progress
        )
        return file(PushReceipt.forExperimentImages(result, at: date), for: result)
    }

    // MARK: - Writing the in-app purchases

    /// Writes the names and descriptions, then files the record of it.
    ///
    /// A dry run builds every request and sends none of them, the way a price
    /// dry run does. It makes no version either, which a real run does not do
    /// on its own: a push writes into a draft somebody made in App Store
    /// Connect.
    @discardableResult
    public func pushProductText(
        _ reading: Reading,
        dryRun: Bool = false,
        at date: Date = .now,
        progress: (@Sendable (String) -> Void)? = nil
    ) async throws -> Outcome<ProductPusher.TextResult> {
        let planned = try plannedProducts(in: reading)

        let result = await ProductPusher(client: client).pushText(
            planned.changes,
            to: planned.remote,
            dryRun: dryRun,
            progress: progress
        )

        // A dry run wrote nothing, so there is nothing to file a record of.
        guard dryRun == false else {
            return Outcome(result: result, receiptURL: nil, receiptFailure: nil)
        }
        return file(PushReceipt.forProductText(result, at: date), for: result)
    }

    /// Writes the prices, then files the record of it.
    ///
    /// Two doors rather than one, matching the two the listing has. It matters
    /// more here: a wrong description is an edit and a wrong price is money.
    ///
    /// A dry run builds every request and sends none of them. What it hands
    /// back is the same body a real run would send, because the same builder
    /// makes both.
    @discardableResult
    public func pushPrices(
        _ reading: Reading,
        dryRun: Bool = false,
        oneCountryAtATime: Bool = false,
        at date: Date = .now,
        progress: (@Sendable (String) -> Void)? = nil
    ) async throws -> Outcome<ProductPusher.PriceResult> {
        let planned = try plannedProducts(in: reading)

        let result = await ProductPusher(client: client).pushPrices(
            planned.changes,
            to: planned.remote,
            dryRun: dryRun,
            oneCountryAtATime: oneCountryAtATime,
            progress: progress
        )

        // A dry run wrote nothing, so there is nothing to file a record of.
        guard dryRun == false else {
            return Outcome(result: result, receiptURL: nil, receiptFailure: nil)
        }
        return file(PushReceipt.forPrices(result, at: date), for: result)
    }

    /// Refuses a reading with no products in it.
    ///
    /// Deliberately not the same guard the listing uses. That one wants a
    /// version folder, and an in-app purchase belongs to no version, so a
    /// folder nobody has made yet must not stop a price going out.
    private func plannedProducts(
        in reading: Reading
    ) throws -> (changes: ChangePlan, remote: RemoteProducts) {
        guard let changes = reading.changes, let remote = reading.remoteProducts else {
            throw ProductPushError.nothingRead
        }
        return (changes, remote)
    }

    /// Refuses a reading that has no plan in it, which is a push against a
    /// version folder that is not there.
    private func planned(in reading: Reading) throws -> (content: VersionContent, changes: ChangePlan) {
        guard let content = reading.content, let changes = reading.changes else {
            throw ProjectError.noSuchVersion(reading.listing.versionString)
        }
        return (content, changes)
    }

    /// Writes the receipt and hands back what happened either way.
    ///
    /// Never throws. App Store Connect has already changed by the time this
    /// runs, so a receipt that cannot be written is worth reporting and is not
    /// worth failing the push over.
    func file<Result: Sendable>(
        _ receipt: PushReceipt,
        for result: Result
    ) -> Outcome<Result> {
        do {
            return try Outcome(
                result: result,
                receiptURL: PushHistory.write(receipt, to: project),
                receiptFailure: nil
            )
        } catch {
            return Outcome(result: result, receiptURL: nil, receiptFailure: "\(error)")
        }
    }
}
