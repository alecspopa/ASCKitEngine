import ASCKitAPI
import ASCKitTestSupport
import Testing
@testable import ASCKitProject

struct TextStatusTests {
    /// Both sides in English only. `live` nil means the version on sale was not read.
    func listing(
        appInfo: [String: String] = [:],
        version: [String: String] = [:],
        live: (appInfo: [String: String], version: [String: String])? = ([:], [:])
    ) -> RemoteListing {
        .fixture(
            versionID: "v2",
            versionString: "1.1",
            appInfoLocalizations: ["en-US": RemoteLocalization(id: "i", locale: "en-US", values: appInfo)],
            versionLocalizations: ["en-US": RemoteLocalization(id: "v", locale: "en-US", values: version)],
            live: live.map {
                LiveTexts(
                    versionString: "1.0",
                    appInfoLocalizations: ["en-US": RemoteLocalization(id: "li", locale: "en-US", values: $0.appInfo)],
                    versionLocalizations: ["en-US": RemoteLocalization(id: "lv", locale: "en-US", values: $0.version)]
                )
            }
        )
    }

    @Test func aFieldTheStoreDoesNotHoldIsNotPushed() {
        let store = listing(version: ["description": "Old words."])
        #expect(store.textStatus(of: .description, locale: "en-US", value: "New words.") == .notPushed)
    }

    @Test func aFieldTheStoreHoldsAndTheLiveVersionDoesNotIsPushed() {
        let store = listing(
            version: ["description": "New words."],
            live: (appInfo: [:], version: ["description": "Old words."])
        )
        #expect(store.textStatus(of: .description, locale: "en-US", value: "New words.") == .pushed)
    }

    @Test func aFieldThatMatchesTheLiveVersionHasNoStatus() {
        let store = listing(
            version: ["description": "Same words."],
            live: (appInfo: [:], version: ["description": "Same words."])
        )
        #expect(store.textStatus(of: .description, locale: "en-US", value: "Same words.") == nil)
    }

    /// The name lives on the app information, so it is compared with the live
    /// app information and not with the version.
    @Test func comparesTheNameWithTheLiveAppInformation() {
        let store = listing(
            appInfo: ["name": "Pantry"],
            version: ["name": "Pantry"],
            live: (appInfo: ["name": "Demo"], version: ["name": "Pantry"])
        )
        #expect(store.textStatus(of: .name, locale: "en-US", value: "Pantry") == .pushed)
    }

    /// Before the first release, every word on the store came from this version.
    @Test func everyStoredFieldOfAFirstVersionIsPushed() {
        let store = listing(version: ["keywords": "pantry"])
        #expect(store.textStatus(of: .keywords, locale: "en-US", value: "pantry") == .pushed)
    }

    @Test func aFieldTheFileLeavesOutHasNoStatus() {
        let store = listing(version: ["description": "Words."])
        #expect(store.textStatus(of: .description, locale: "en-US", value: nil) == nil)
    }

    /// Apple returns an empty string for a field nobody set.
    @Test func anEmptyStoreFieldMatchesAnEmptyFileField() {
        let store = listing(version: ["whatsNew": ""], live: (appInfo: [:], version: [:]))
        #expect(store.textStatus(of: .whatsNew, locale: "en-US", value: "") == nil)
    }

    @Test func aLanguageTheStoreDoesNotHoldIsNotPushed() {
        let store = listing()
        #expect(store.textStatus(of: .description, locale: "fr-FR", value: "Mots.") == .notPushed)
    }

    @Test func saysNothingOfAStoredFieldWhenTheLiveVersionWasNotRead() {
        let store = listing(version: ["description": "Words."], live: nil)
        #expect(store.textStatus(of: .description, locale: "en-US", value: "Words.") == nil)
        #expect(store.textStatus(of: .description, locale: "en-US", value: "Other.") == .notPushed)
    }
}
