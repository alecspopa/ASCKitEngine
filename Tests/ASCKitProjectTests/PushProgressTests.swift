import ASCKitAPI
import Foundation
import Testing
@testable import ASCKitProject

/// What the bar in the publish sheet counts.
///
/// The number has to come off the plan, because the plan is the only thing that
/// knows what a press is about to do before it does any of it.
struct PushProgressTests {
    func textChange(_ locale: String, _ field: MetadataField) -> ChangePlan.TextChange {
        ChangePlan.TextChange(
            locale: locale,
            field: field,
            action: .change,
            oldValue: "before",
            newValue: "after"
        )
    }

    func productTextChange(
        _ productID: String,
        _ locale: String,
        _ field: ProductField
    ) -> ChangePlan.ProductTextChange {
        ChangePlan.ProductTextChange(
            productID: productID,
            locale: locale,
            field: field,
            action: .change,
            oldValue: "before",
            newValue: "after"
        )
    }

    func priceChange(_ productID: String, changing: Bool) -> ChangePlan.PriceChange {
        ChangePlan.PriceChange(
            productID: productID,
            kind: .nonConsumable,
            baseTerritory: "USA",
            baseAmount: "4.99",
            curveID: "purchasing-power",
            replacesWholeSchedule: true,
            preserveCurrentPrice: nil,
            rows: [ChangePlan.PriceChange.Row(
                territory: "USA",
                planType: .upfront,
                currency: "USD",
                pricePointID: "point-USA",
                oldAmount: "1.99",
                newAmount: changing ? "4.99" : "1.99",
                direction: changing ? .up : .same,
                source: .curve(band: nil),
                roundedUpBy: "0"
            )],
            skipped: []
        )
    }

    func screenshotPlan(
        _ locale: String,
        removing: Int,
        uploading: Int
    ) -> ChangePlan.ScreenshotPlan {
        .stub(locale, removing: removing, uploading: uploading)
    }

    func plan(
        textChanges: [ChangePlan.TextChange] = [],
        productTextChanges: [ChangePlan.ProductTextChange] = [],
        pricePlans: [ChangePlan.PriceChange] = [],
        screenshotPlans: [ChangePlan.ScreenshotPlan] = []
    ) -> ChangePlan {
        ChangePlan(
            versionString: "1.0",
            versionState: nil,
            textChanges: textChanges,
            missingLocales: [],
            screenshotPlans: screenshotPlans,
            productTextChanges: productTextChanges,
            pricePlans: pricePlans,
            newProducts: [],
            blocked: [],
            skipped: []
        )
    }

    // MARK: - What each part has to do

    /// A language goes out in one or two requests, whatever moved in it. Four
    /// fields in two languages is two steps, not four.
    @Test func countsTheTextOneLanguageAtATime() {
        let changes = plan(textChanges: [
            textChange("en-US", .description),
            textChange("en-US", .keywords),
            textChange("de-DE", .description),
            textChange("de-DE", .keywords)
        ])

        #expect(PushProgress.steps(for: .appInformation, in: changes) == 2)
    }

    /// The name and the description of one purchase in one language go together
    /// in one request, so the pair is one step.
    @Test func countsAPurchaseOneLanguageAtATime() {
        let changes = plan(productTextChanges: [
            productTextChange("com.example.pro", "en-US", .name),
            productTextChange("com.example.pro", "en-US", .description),
            productTextChange("com.example.pro", "de-DE", .name)
        ])

        #expect(PushProgress.steps(for: .purchases, in: changes) == 2)
    }

    /// Every country of one purchase goes in one request, so a purchase is one
    /// step however many countries move.
    @Test func countsThePricesOnePurchaseAtATime() {
        let changes = plan(pricePlans: [
            priceChange("com.example.pro", changing: true),
            priceChange("com.example.plus", changing: true),
            priceChange("com.example.old", changing: false)
        ])

        #expect(PushProgress.steps(for: .prices, in: changes) == 2)
    }

    /// Each file goes up, the old placements come off, the new ones are made,
    /// then the order is set.
    @Test func countsEveryImageAndTheStepsAroundIt() {
        let changes = plan(screenshotPlans: [screenshotPlan("en-US", removing: 3, uploading: 4)])

        #expect(PushProgress.steps(for: .screenshots, in: changes) == 7)
    }

    /// Nothing comes off, and one image needs no order. So the steps are the
    /// upload and the placement.
    @Test func countsNeitherEmptyingNorOrderingWhenThereIsNothingToDo() {
        let changes = plan(screenshotPlans: [screenshotPlan("en-US", removing: 0, uploading: 1)])

        #expect(PushProgress.steps(for: .screenshots, in: changes) == 2)
    }

    /// The library already holds the file, so nothing goes up. The one step is
    /// the placement.
    @Test func countsNoUploadForAFileTheLibraryHolds() {
        let slot = LibrarySlot(group: "G", type: .appScreenshot, wanted: ["asset1"], checksums: ["x"], current: [])
        let changes = plan(screenshotPlans: [
            .init(locale: "en-US", deviceClass: .iPhone69, localFiles: [], library: slot)
        ])

        #expect(PushProgress.steps(for: .screenshots, in: changes) == 1)
    }

    // MARK: - What one press adds up to

    /// The bar measures the press, so an unticked part is not in the total even
    /// when the plan is full of work for it.
    @Test func countsOnlyTheTickedParts() {
        let changes = plan(
            textChanges: [textChange("en-US", .description)],
            screenshotPlans: [screenshotPlan("en-US", removing: 3, uploading: 4)]
        )

        #expect(PushProgress([.appInformation], in: changes).total == 1)
        #expect(PushProgress([.appInformation, .screenshots], in: changes).total == 8)
    }

    @Test func saysWhatTheStepThatStartedLastIs() {
        var progress = PushProgress([.appInformation], in: plan(textChanges: [
            textChange("en-US", .description),
            textChange("de-DE", .description)
        ]))

        #expect(progress.step == nil)
        progress.start("en-US")
        #expect(progress.step == "en-US")
        #expect(progress.completed == 1)
    }

    /// The plan counts what a push is about to do, and App Store Connect can
    /// hold an image the plan did not expect. A bar that runs off the end of
    /// itself is worse than one that waits at the end.
    @Test func stopsAtTheTotalWhenMoreStepsArriveThanThePlanExpected() {
        var progress = PushProgress(
            [.appInformation], in: plan(textChanges: [textChange("en-US", .description)])
        )

        progress.start("en-US")
        progress.start("de-DE")

        #expect(progress.completed == 1)
    }

    /// A language with no file behind it is skipped without a word. The bar
    /// would sit short of the end for the rest of the push, so the end of a
    /// part puts it where the finished parts say it is.
    @Test func fillsInTheStepsThatWentBySilently() {
        var progress = PushProgress([.appInformation, .prices], in: plan(
            textChanges: [textChange("en-US", .description), textChange("de-DE", .description)],
            pricePlans: [priceChange("com.example.pro", changing: true)]
        ))

        progress.start("en-US")
        progress.finish(.appInformation)

        #expect(progress.completed == 2)
        #expect(progress.total == 3)
    }

    /// Every part done is a full bar, which is what a person watching it waits
    /// for.
    @Test func endsFullWhenEveryPartHasRun() {
        var progress = PushProgress([.appInformation, .screenshots], in: plan(
            textChanges: [textChange("en-US", .description)],
            screenshotPlans: [screenshotPlan("en-US", removing: 3, uploading: 4)]
        ))

        progress.finish(.appInformation)
        progress.finish(.screenshots)

        #expect(progress.completed == progress.total)
    }
}
