import ASCKitAPI
import Foundation
import Testing
@testable import ASCKitProject

struct ChangePlanFormatterTests {
    func plan(
        textChanges: [ChangePlan.TextChange] = [],
        missingLocales: [String] = [],
        screenshotPlans: [ChangePlan.ScreenshotPlan] = [],
        blocked: [ChangePlan.Blocked] = [],
        skipped: [ChangePlan.Skipped] = []
    ) -> ChangePlan {
        ChangePlan(
            versionString: "1.0",
            versionState: .prepareForSubmission,
            textChanges: textChanges,
            missingLocales: missingLocales,
            screenshotPlans: screenshotPlans,
            blocked: blocked,
            skipped: skipped
        )
    }

    func change(
        locale: String = "en-US",
        field: MetadataField = .subtitle,
        action: ChangePlan.TextChange.Action = .change,
        oldValue: String? = "Something older",
        newValue: String = "Shared pantry list"
    ) -> ChangePlan.TextChange {
        .init(locale: locale, field: field, action: action, oldValue: oldValue, newValue: newValue)
    }

    func screenshots(_ action: ChangePlan.ScreenshotPlan.Action) -> ChangePlan.ScreenshotPlan {
        switch action {
        case .unchanged: .stub(removing: 0, uploading: 0)
        case let .replace(removing, adding): .stub(removing: removing, uploading: adding)
        }
    }

    // MARK: - Nothing to do

    @Test func saysPlainlyWhenThereIsNothingToChange() {
        #expect(ChangePlanFormatter.lines(for: plan())
            == ["Nothing to change. App Store Connect already matches these files."])
        #expect(ChangePlanFormatter.summary(plan()) == "No changes.")
    }

    /// A set that already matches must not be listed as a change, because the
    /// only way to change one is to delete it first.
    @Test func doesNotListAScreenshotSetThatMatches() {
        let lines = ChangePlanFormatter.lines(for: plan(screenshotPlans: [screenshots(.unchanged)]))
        #expect(lines.contains { $0.contains("Screenshots:") } == false)
    }

    // MARK: - Text

    @Test func showsBothValuesForAChangedField() {
        let lines = ChangePlanFormatter.lines(for: plan(textChanges: [change()]))
        #expect(lines.contains("      was:  Something older"))
        #expect(lines.contains { $0.contains("now:") && $0.contains("Shared pantry list") })
    }

    @Test func showsOnlyTheNewValueForAFieldBeingAdded() {
        let lines = ChangePlanFormatter.lines(for: plan(
            textChanges: [change(action: .add, oldValue: nil)]
        ))
        #expect(lines.contains { $0.contains("was:") } == false)
        #expect(lines.contains { $0.contains("new:") })
    }

    /// A description is 4000 characters. Nobody reads that on a terminal.
    @Test func shortensAValueTooLongToRead() {
        let long = String(repeating: "a", count: 500)
        let lines = ChangePlanFormatter.lines(for: plan(
            textChanges: [change(field: .description, oldValue: nil, newValue: long)]
        ))
        let shown = try? #require(lines.first { $0.contains("new:") })
        #expect(shown?.count ?? 0 < 100)
        #expect(shown?.hasSuffix("…") == true)
    }

    @Test func putsNewlinesOntoOneLine() {
        let lines = ChangePlanFormatter.lines(for: plan(
            textChanges: [change(field: .description, oldValue: nil, newValue: "One\nTwo")]
        ))
        #expect(lines.contains { $0.contains("One Two") })
    }

    @Test func groupsChangesByLanguage() {
        let lines = ChangePlanFormatter.lines(for: plan(textChanges: [
            change(locale: "en-US", field: .subtitle),
            change(locale: "en-US", field: .keywords),
            change(locale: "de-DE", field: .subtitle)
        ]))
        #expect(lines.filter { $0 == "  en-US" }.count == 1)
        #expect(lines.filter { $0 == "  de-DE" }.count == 1)
    }

    // MARK: - Screenshots

    @Test(arguments: [
        (ChangePlan.ScreenshotPlan.Action.replace(removing: 0, adding: 6), "add 6 images"),
        (.replace(removing: 6, adding: 0), "remove all 6 images"),
        (.replace(removing: 6, adding: 6), "remove 6 images, then add 6 images")
    ])
    func saysWhatWouldHappenToASet(action: ChangePlan.ScreenshotPlan.Action, expected: String) {
        let lines = ChangePlanFormatter.lines(for: plan(screenshotPlans: [screenshots(action)]))
        #expect(lines.contains { $0.hasSuffix(expected) })
    }

    @Test func writesOneImageInTheSingular() {
        let lines = ChangePlanFormatter.lines(for: plan(
            screenshotPlans: [screenshots(.replace(removing: 0, adding: 1))]
        ))
        #expect(lines.contains { $0.hasSuffix("add 1 image") })
    }

    // MARK: - The rest

    @Test func namesLanguagesAppStoreConnectHasNoPageFor() {
        let lines = ChangePlanFormatter.lines(for: plan(missingLocales: ["de-DE", "ja"]))
        #expect(lines.contains { $0.contains("no page in") && $0.contains("de-DE, ja") })
    }

    @Test func putsWhatCannotBeDoneFirst() {
        let lines = ChangePlanFormatter.lines(for: plan(
            textChanges: [change()],
            blocked: [.init(reason: "Version 1.0 is IN_REVIEW.", affects: "1 change", cause: .versionStatus, parts: [.appInformation])]
        ))
        #expect(lines.first == "Cannot be done now:")
    }

    @Test func saysWhyALanguageWasLeftOut() {
        let lines = ChangePlanFormatter.lines(for: plan(
            skipped: [.init(locale: "de-DE", reason: "marked needs_human")]
        ))
        #expect(lines.contains("  de-DE, marked needs_human"))
    }

    // MARK: - The summary

    @Test func countsFieldsAndSetsSeparately() {
        let summary = ChangePlanFormatter.summary(plan(
            textChanges: [change(), change(field: .keywords)],
            screenshotPlans: [screenshots(.replace(removing: 1, adding: 1))]
        ))
        #expect(summary == "Would change 2 fields and 1 screenshot set.")
    }

    @Test func namesTheVersionStatusWhenThatIsWhatBlocks() {
        let summary = ChangePlanFormatter.summary(plan(
            textChanges: [change()],
            blocked: [.init(reason: "Version 1.0 is IN_REVIEW.", affects: "1 change", cause: .versionStatus, parts: [.appInformation])]
        ))
        #expect(summary == "Would change 1 field. Version status does not allow any more updates.")
    }

    @Test func countsWhatIsBlockedWhenAPurchaseBlocksIt() {
        let summary = ChangePlanFormatter.summary(plan(
            textChanges: [change()],
            blocked: [.init(reason: "pro.year is in review.", affects: "pro.year", cause: .product, parts: [.purchases, .prices])]
        ))
        #expect(summary == "Would change 1 field. 1 thing cannot be done in this state.")
    }
}
