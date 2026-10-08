import ASCKitAPI
import Foundation
import Testing
@testable import ASCKitProject

/// Which of the four parts of a push can go, and the words beside each one.
///
/// The publish sheet has one button now, so a part that cannot go has to say so
/// itself. These are the rules it says it by.
struct PublishReadinessTests {
    // MARK: - Builders

    func plan(
        textChanges: [ChangePlan.TextChange] = [],
        screenshotPlans: [ChangePlan.ScreenshotPlan] = [],
        productTextChanges: [ChangePlan.ProductTextChange] = [],
        pricePlans: [ChangePlan.PriceChange] = [],
        blocked: [ChangePlan.Blocked] = []
    ) -> ChangePlan {
        ChangePlan(
            versionString: "1.0",
            versionState: .prepareForSubmission,
            textChanges: textChanges,
            missingLocales: [],
            screenshotPlans: screenshotPlans,
            productTextChanges: productTextChanges,
            pricePlans: pricePlans,
            blocked: blocked,
            skipped: []
        )
    }

    func text(_ locale: String = "en-US", _ field: MetadataField = .subtitle) -> ChangePlan.TextChange {
        .init(locale: locale, field: field, action: .change, oldValue: "Was", newValue: "Now")
    }

    func productText(_ productID: String = "com.example.pro") -> ChangePlan.ProductTextChange {
        .init(
            productID: productID, locale: "en-US", field: .name,
            action: .change, oldValue: "Was", newValue: "Now"
        )
    }

    func screenshots(
        _ locale: String = "en-US",
        removing: Int = 0,
        uploading: Int = 3
    ) -> ChangePlan.ScreenshotPlan {
        .stub(locale, removing: removing, uploading: uploading)
    }

    func row(
        _ territory: String,
        _ amount: Money,
        old: Money? = "3.99",
        direction: ChangePlan.PriceChange.Direction = .up
    ) -> ChangePlan.PriceChange.Row {
        .init(
            territory: territory,
            planType: .upfront,
            currency: "USD",
            pricePointID: "\(territory)-\(amount)",
            oldAmount: old,
            newAmount: amount,
            direction: direction,
            source: .curve(band: nil),
            roundedUpBy: "0"
        )
    }

    func prices(
        _ rows: [ChangePlan.PriceChange.Row],
        productID: String = "com.example.pro"
    ) -> ChangePlan.PriceChange {
        .init(
            productID: productID,
            kind: .autoRenewableSubscription,
            baseTerritory: "USA",
            baseAmount: "4.99",
            curveID: "purchasing-power",
            replacesWholeSchedule: false,
            preserveCurrentPrice: true,
            rows: rows,
            skipped: []
        )
    }

    func state(
        _ part: PublishPart,
        _ plan: ChangePlan?,
        versionToCreate: String? = nil,
        stillArrivingImages: Int = 0,
        agreedToRises: Bool = false
    ) -> PublishAvailability {
        PublishReadiness.availability(of: part, given: .init(
            plan: plan,
            versionToCreate: versionToCreate,
            stillArrivingImages: stillArrivingImages,
            agreedToRises: agreedToRises
        ))
    }

    // MARK: - Nothing read

    @Test func saysNothingHasBeenReadYet() {
        for part in PublishPart.pushOrder {
            #expect(state(part, nil) == .blocked(
                "Nothing has been read yet. Read App Store Connect first."
            ))
        }
    }

    // MARK: - A version folder nobody made

    /// A product hangs off the app rather than off a version, so a folder
    /// nobody has made yet must not hold up a price.
    @Test func aMissingVersionFolderBlocksTheListingAndNotThePurchases() {
        let ready = plan(
            textChanges: [text()],
            screenshotPlans: [screenshots()],
            productTextChanges: [productText()],
            pricePlans: [prices([row("USA", "4.99")])]
        )

        let reason = "App Store Connect is on version 1.1, and there is no folder for it here."
        #expect(state(.appInformation, ready, versionToCreate: "1.1") == .blocked(reason))
        #expect(state(.screenshots, ready, versionToCreate: "1.1") == .blocked(reason))
        #expect(state(.purchases, ready, versionToCreate: "1.1").canGo)
        #expect(state(.prices, ready, versionToCreate: "1.1", agreedToRises: true).canGo)
    }

    // MARK: - Blocked by the version's state

    /// A locked version used to hold up the in-app purchases too, which
    /// belong to no version.
    @Test func aBlockHoldsUpOnlyThePartsItNames() {
        let stuck = plan(
            textChanges: [text()],
            productTextChanges: [productText()],
            blocked: [.init(
                reason: "The version is in review.", affects: "every field",
                cause: .versionStatus, parts: [.appInformation, .screenshots]
            )]
        )

        #expect(state(.appInformation, stuck) == .blocked("The version is in review. Affects every field."))
        #expect(state(.screenshots, stuck) == .blocked("The version is in review. Affects every field."))
        #expect(state(.purchases, stuck).canGo)
        #expect(state(.prices, stuck) == .nothingToDo)
    }

    @Test func countsTheReasonsItDoesNotHaveRoomToName() {
        let stuck = plan(blocked: [
            .init(reason: "The version is in review.", affects: "every field", cause: .versionStatus, parts: [.appInformation]),
            .init(reason: "The name cannot change now.", affects: "the name", cause: .versionStatus, parts: [.appInformation]),
            .init(reason: "The subtitle cannot change now.", affects: "the subtitle", cause: .versionStatus, parts: [.appInformation])
        ])

        #expect(state(.appInformation, stuck) == .blocked(
            "The version is in review. Affects every field. And 2 more."
        ))
    }

    // MARK: - Nothing to do

    @Test func aPartWithNothingToDoSaysSoRatherThanRefusing() {
        #expect(state(.appInformation, plan()) == .nothingToDo)
        #expect(state(.purchases, plan()) == .nothingToDo)
        #expect(state(.prices, plan()) == .nothingToDo)
        #expect(state(.screenshots, plan()) == .nothingToDo)
    }

    /// A slot that already holds these assets in this order is not a change.
    @Test func aScreenshotSetThatMatchesIsNothingToDo() {
        let current = [Placed.placement("p1", asset: "a1"), Placed.placement("p2", asset: "a2")]
        let matching = ChangePlan.ScreenshotPlan(
            locale: "en-US", deviceClass: .iPhone69, localFiles: [],
            library: LibrarySlot(group: Placed.group, type: .appScreenshot, wanted: ["a1", "a2"],
                                 checksums: ["x", "y"], current: current)
        )
        #expect(state(.screenshots, plan(screenshotPlans: [matching])) == .nothingToDo)
    }

    // MARK: - The two agreements

    @Test func aRiseNeedsTheTick() {
        let rising = plan(pricePlans: [prices([row("USA", "5.99"), row("CAN", "7.99")])])

        #expect(state(.prices, rising) == .blocked(
            "2 prices would go up. Read them and tick the box."
        ))
        #expect(state(.prices, rising, agreedToRises: true).canGo)
    }

    /// The singular is a plural rule in the catalog, so this checks the count
    /// reaches the sentence rather than checking the wording around it.
    @Test func oneRiseStillNamesItsCount() {
        let rising = plan(pricePlans: [prices([row("USA", "5.99")])])
        #expect(state(.prices, rising).detail.contains("1 price"))
    }

    /// A cut is not a rise, and nobody has to agree to one.
    @Test func aPriceThatOnlyFallsGoesWithNoTick() {
        let falling = plan(pricePlans: [
            prices([row("USA", "2.99", old: "4.99", direction: .down)])
        ])
        #expect(state(.prices, falling).canGo)
    }

    // MARK: - The set that was just pushed

    /// An asset still processing can still fail, and then its slot plans
    /// again, so the images wait for it.
    @Test func aSetAppStoreConnectHasNotFinishedWithIsNotOfferedAgain() {
        let shots = plan(screenshotPlans: [screenshots(removing: 4, uploading: 4)])

        #expect(state(.screenshots, shots, stillArrivingImages: 4) == .blocked(
            "App Store Connect has not finished with 4 images. Read it again in a moment."
        ))
    }

    /// The singular is a plural rule in the catalog, so this checks the count
    /// reaches the sentence rather than checking the wording around it.
    @Test func oneImageStillArrivingStillNamesItsCount() {
        let shots = plan(screenshotPlans: [screenshots(removing: 1, uploading: 1)])

        #expect(state(.screenshots, shots, stillArrivingImages: 1).detail.contains("with 1 image"))
    }

    /// An image on its way holds up the images and nothing else. The words of a
    /// language have nothing to do with it.
    @Test func anImageStillArrivingHoldsUpTheImagesAlone() {
        let both = plan(
            textChanges: [text()],
            screenshotPlans: [screenshots(removing: 4, uploading: 4)]
        )

        #expect(state(.appInformation, both, stillArrivingImages: 4).canGo)
    }

    /// The order of the reasons. A plan with no price change must never mention
    /// a rise, because there is not one.
    @Test func nothingToDoBeatsARiseNobodyAgreedTo() {
        let words = plan(textChanges: [text()])
        #expect(state(.prices, words) == .nothingToDo)
    }

    // MARK: - The counts

    @Test func aPartThatCanGoCarriesItsCount() {
        let ready = plan(textChanges: [text("en-US"), text("en-US", .keywords), text("ro")])
        #expect(state(.appInformation, ready) == .ready("3 fields, 2 languages"))
    }

    @Test func everyPartIsAsked() {
        let states = PublishReadiness.availability(given: .init(plan: plan()))
        #expect(states.count == 4)
    }

    @Test func countsFieldsAndPurchases() {
        let words = plan(productTextChanges: [
            productText("com.example.pro"), productText("com.example.tips")
        ])
        #expect(ChangePlanFormatter.count(of: .purchases, in: words) == "2 fields, 2 purchases")
    }

    @Test func countsPricesAcrossProducts() {
        let money = plan(pricePlans: [
            prices([row("USA", "5.99"), row("CAN", "7.99")], productID: "com.example.pro"),
            prices([row("USA", "1.99")], productID: "com.example.tips")
        ])
        #expect(ChangePlanFormatter.count(of: .prices, in: money) == "3 prices, 2 products")
    }

    @Test func oneOfEachIsSingular() {
        let one = plan(textChanges: [text()])
        #expect(ChangePlanFormatter.count(of: .appInformation, in: one) == "1 field, 1 language")
    }

    @Test func countsSetsAndImages() {
        let shots = plan(screenshotPlans: [
            screenshots("en-US", removing: 2, uploading: 3),
            screenshots("ro", removing: 0, uploading: 3)
        ])
        #expect(ChangePlanFormatter.count(of: .screenshots, in: shots) == "2 sets, 6 images")
    }

    /// A plan of previews and art alone still says what the part writes,
    /// where it used to read "0 sets, removing 0 images".
    @Test func countsPreviewSetsAndArt() {
        let slot = LibrarySlot(group: "G", type: .appPreview, wanted: [nil], checksums: ["x"], current: [])
        let art = LibrarySlot(group: "DEFAULT_PROFILE", type: .productPageHeader, wanted: [nil], checksums: ["y"],
                              current: [])
        let changes = ChangePlan(
            versionString: "1.0", versionState: .prepareForSubmission, textChanges: [], missingLocales: [],
            screenshotPlans: [],
            previewPlans: [.init(locale: "en-US", deviceClass: .iPhone69, localFiles: [], library: slot)],
            creativePlans: [CreativePlan(locale: "en-US", role: .header, file: nil, usesHeader: false, library: art)],
            blocked: [], skipped: []
        )
        #expect(ChangePlanFormatter.count(of: .screenshots, in: changes)
            == "1 preview set and header and search results art")
    }

    @Test func countsScreenshotsAndPreviewsTogether() {
        let slot = LibrarySlot(group: "G", type: .appPreview, wanted: [nil, nil], checksums: ["x", "y"], current: [])
        let changes = ChangePlan(
            versionString: "1.0", versionState: .prepareForSubmission, textChanges: [], missingLocales: [],
            screenshotPlans: [screenshots(removing: 0, uploading: 2)],
            previewPlans: [
                .init(locale: "en-US", deviceClass: .iPhone69, localFiles: [], library: slot),
                .init(locale: "de-DE", deviceClass: .iPhone69, localFiles: [], library: slot)
            ],
            blocked: [], skipped: []
        )
        #expect(ChangePlanFormatter.count(of: .screenshots, in: changes) == "1 set, 2 images and 2 preview sets")
    }

    @Test func aSetThatOnlyMovesSaysSo() {
        let current = [Placed.placement("p1", asset: "a1"), Placed.placement("p2", asset: "a2")]
        let slot = LibrarySlot(group: Placed.group, type: .appScreenshot, wanted: ["a2", "a1"],
                               checksums: ["x", "y"], current: current)
        let changes = plan(screenshotPlans: [.init(locale: "en-US", deviceClass: .iPhone69, localFiles: [],
                                                   library: slot)])
        #expect(ChangePlanFormatter.count(of: .screenshots, in: changes) == "1 set in a new order")
    }

    /// "1 set, 0 images" reads as a fault. What this does is empty a set.
    @Test func aSetThatOnlyEmptiesSaysSo() {
        let shots = plan(screenshotPlans: [screenshots(removing: 9, uploading: 0)])
        #expect(ChangePlanFormatter.count(of: .screenshots, in: shots)
            == "1 set, removing 9 images")
    }

    @Test func nothingToChangeCountsAsNothing() {
        #expect(ChangePlanFormatter.count(of: .appInformation, in: plan()) == nil)
    }

    // MARK: - The notice above the button

    @Test func nothingTickedSaysNothing() {
        #expect(PublishReadiness.notice(for: [], given: .init(plan: plan())) == nil)
    }

    @Test func theNoticeAlwaysSaysThatAPushWritesOver() {
        let notice = PublishReadiness.notice(
            for: [.appInformation], given: .init(plan: plan(textChanges: [text()]))
        )
        #expect(notice == "Push writes over what App Store Connect holds now.")
    }

    @Test func theNoticeNamesWhatCannotBeTakenBack() {
        let rising = plan(
            screenshotPlans: [screenshots()],
            pricePlans: [prices([row("USA", "5.99")])]
        )
        let notice = PublishReadiness.notice(
            for: [.screenshots, .prices], given: .init(plan: rising, agreedToRises: true)
        )

        // The count is checked on its own, because the singular of the last
        // sentence is a plural rule in the catalog.
        #expect(notice?.hasPrefix("Push writes over what App Store Connect holds now. "
                + "A screenshot taken off a set stays in the app's asset library. ") == true)
        #expect(notice?.contains("1 price") == true)
        #expect(notice?.hasSuffix("and a rise cannot be taken back.") == true)
    }

    /// A rise nobody is writing is not worth a warning.
    @Test func theNoticeLeavesOutARisePricesAreNotTickedFor() {
        let rising = plan(pricePlans: [prices([row("USA", "5.99")])])
        let notice = PublishReadiness.notice(for: [.appInformation], given: .init(plan: rising))
        #expect(notice == "Push writes over what App Store Connect holds now.")
    }
}
