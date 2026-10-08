import Foundation
import Testing
@testable import ASCKitProject

/// Xcode's language list and the App Store's do not agree. Where there is one
/// answer this gives it. Where there are several it must say so rather than
/// pick, because a listing written in the wrong English is one nobody notices
/// is wrong.
struct RegionMatchTests {
    @Test func findsTheOneAnswerWhenThereIsOne() {
        #expect(RegionMatch.outcome(for: "de") == .one("de-DE"))
        #expect(RegionMatch.outcome(for: "nl") == .one("nl-NL"))
        #expect(RegionMatch.outcome(for: "ja") == .one("ja"))
        #expect(RegionMatch.outcome(for: "it") == .one("it"))
    }

    /// A code the App Store already takes passes through untouched, including
    /// the ones with a script rather than a region.
    @Test func leavesACodeTheAppStoreAlreadyTakes() {
        #expect(RegionMatch.outcome(for: "zh-Hans") == .one("zh-Hans"))
        #expect(RegionMatch.outcome(for: "pt-BR") == .one("pt-BR"))
        #expect(RegionMatch.outcome(for: "en-GB") == .one("en-GB"))
    }

    @Test func namesEveryChoiceWhenThereIsMoreThanOne() {
        #expect(RegionMatch.outcome(for: "en") == .several(["en-AU", "en-CA", "en-GB", "en-US"]))
        #expect(RegionMatch.outcome(for: "es") == .several(["es-ES", "es-MX"]))
        #expect(RegionMatch.outcome(for: "fr") == .several(["fr-CA", "fr-FR"]))
    }

    @Test func saysWhenTheAppStoreHasNoSuchLanguage() {
        #expect(RegionMatch.outcome(for: "cy") == .none)
        #expect(RegionMatch.outcome(for: "eo") == .none)
    }

    @Test func keepsTheOrderXcodeListedThemIn() {
        let outcomes = RegionMatch.outcomes(for: ["de", "en", "ja"])
        #expect(outcomes.map(\.region) == ["de", "en", "ja"])
    }

    @Test func namesOnlyTheRegionsSomebodyHasToChooseFor() {
        #expect(RegionMatch.needingAChoice(in: ["de", "en", "ja", "es"]) == ["en", "es"])
        #expect(RegionMatch.needingAChoice(in: ["de", "ja"]).isEmpty)
    }

    /// What a project can be scaffolded with straight away. An ambiguous region
    /// is left out rather than guessed at.
    @Test func resolvesOnlyWhatNeedsNoChoosing() {
        #expect(RegionMatch.resolved(in: ["de", "en", "ja"]) == ["de-DE", "ja"])
        #expect(RegionMatch.resolved(in: ["en"]).isEmpty)
    }
}
