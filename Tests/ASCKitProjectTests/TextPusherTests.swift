import ASCKitAPI
import ASCKitTestSupport
import Foundation
import Testing
@testable import ASCKitProject

/// The pusher works from a plan rather than from the files, so what is written
/// is exactly what was shown before anyone agreed to it.
struct TextPusherTests {
    // MARK: - Setting up both sides

    /// App Store Connect holds a localization for every language its store
    /// page is in, with an empty string in a field nobody has set. ASCKit
    /// writes into those and never makes one, so a language a test pushes has
    /// to be in `locales` here.
    func listing(
        appInfoID: String? = "info1",
        locales: [String] = ["en-US"],
        appInfo: [String: String] = [:],
        version: [String: String] = [:]
    ) -> RemoteListing {
        func localizations(_ prefix: String, of values: [String: String]) -> [String: RemoteLocalization] {
            Dictionary(uniqueKeysWithValues: locales.map { locale in
                (locale, RemoteLocalization(
                    id: "\(prefix)-\(locale)",
                    locale: locale,
                    values: locale == "en-US" ? values : [:]
                ))
            })
        }

        return RemoteListing(
            appID: "app1",
            appName: "Demo",
            bundleID: "com.example.Demo",
            appInfoID: appInfoID,
            appInfoState: .prepareForSubmission,
            versionID: "ver1",
            versionString: "1.0",
            versionState: .prepareForSubmission,
            appInfoLocalizations: localizations("i", of: appInfo),
            versionLocalizations: localizations("v", of: version),
            screenshotSets: []
        )
    }

    func plan(_ changes: [ChangePlan.TextChange]) -> ChangePlan {
        ChangePlan(
            versionString: "1.0",
            versionState: .prepareForSubmission,
            textChanges: changes,
            missingLocales: [],
            screenshotPlans: [],
            blocked: [],
            skipped: []
        )
    }

    func change(
        _ field: MetadataField,
        locale: String = "en-US",
        newValue: String = "something"
    ) -> ChangePlan.TextChange {
        .init(locale: locale, field: field, action: .change, oldValue: "old", newValue: newValue)
    }

    func information(_ fields: AppInformation.Fields, locale: String = "en-US") -> [String: AppInformation] {
        [locale: AppInformation(locale: locale, status: .approved, fields: fields)]
    }

    // MARK: - Only what the plan named

    /// The whole point of pushing from a plan. A field the plan did not name is
    /// not sent, even though the app information file has a value for it.
    @Test func sendsOnlyTheFieldsThePlanNamed() async throws {
        let transport = StubTransport(.ok(#"{"data":{"type":"x","id":"v-en"}}"#))
        let pusher = try TextPusher(client: ASCClient.stubbed(transport: transport))

        let result = await pusher.push(
            plan([change(.keywords, newValue: "household,restock")]),
            to: listing(version: ["keywords": "old"]),
            localInformation: information(AppInformation.Fields(
                keywords: "household,restock",
                description: "This has not changed and must not be sent."
            ))
        )

        #expect(result.written == ["en-US"])
        let body = try #require(await transport.request(at: 0).httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let attributes = try #require((json["data"] as? [String: Any])?["attributes"] as? [String: Any])

        #expect(attributes["keywords"] as? String == "household,restock")
        #expect(attributes["description"] == nil)
    }

    /// Name and subtitle go to one resource, everything else to another, so a
    /// language changing both takes two calls.
    @Test func splitsAcrossBothResourcesWhenBothKindsChanged() async throws {
        let transport = StubTransport([
            .ok(#"{"data":{"type":"appInfoLocalizations","id":"i-en"}}"#),
            .ok(#"{"data":{"type":"appStoreVersionLocalizations","id":"v-en"}}"#)
        ])
        let pusher = try TextPusher(client: ASCClient.stubbed(transport: transport))

        _ = await pusher.push(
            plan([change(.subtitle), change(.keywords)]),
            to: listing(appInfo: ["subtitle": "old"], version: ["keywords": "old"]),
            localInformation: information(AppInformation.Fields(subtitle: "New subtitle", keywords: "one,two"))
        )

        let paths = await transport.requests.compactMap(\.url?.path)
        #expect(paths == ["/v1/appInfoLocalizations/i-en-US", "/v1/appStoreVersionLocalizations/v-en-US"])
    }

    @Test func makesOnlyOneCallWhenOnlyVersionFieldsChanged() async throws {
        let transport = StubTransport(.ok(#"{"data":{"type":"x","id":"v-en"}}"#))
        let pusher = try TextPusher(client: ASCClient.stubbed(transport: transport))

        _ = await pusher.push(
            plan([change(.description)]),
            to: listing(version: ["description": "old"]),
            localInformation: information(AppInformation.Fields(description: "Know what you have."))
        )
        #expect(await transport.requestCount == 1)
    }

    // MARK: - Languages that are not there yet

    /// ASCKit never makes a language on App Store Connect. A store page is what
    /// people read, and one that turns up because a file was on disk is a page
    /// nobody decided to publish.
    @Test func refusesALanguageAppStoreConnectDoesNotHave() async throws {
        let transport = StubTransport([])
        let pusher = try TextPusher(client: ASCClient.stubbed(transport: transport))

        let result = await pusher.push(
            plan([change(.description, locale: "de-DE")]),
            to: listing(version: ["description": "old"]),
            localInformation: information(AppInformation.Fields(description: "Wissen, was da ist."), locale: "de-DE")
        )

        #expect(result.written.isEmpty)
        #expect(result.failed.first?.locale == "de-DE")
        #expect(result.failed.first?.message.contains("never makes one") == true)
        #expect(await transport.requestCount == 0)
    }

    @Test func updatesALanguageThatIsAlreadyThere() async throws {
        let transport = StubTransport(.ok(#"{"data":{"type":"x","id":"v-en"}}"#))
        let pusher = try TextPusher(client: ASCClient.stubbed(transport: transport))

        _ = await pusher.push(
            plan([change(.description)]),
            to: listing(version: ["description": "old"]),
            localInformation: information(AppInformation.Fields(description: "Know what you have."))
        )
        #expect(await transport.request(at: 0).httpMethod == "PATCH")
    }

    // MARK: - When something refuses

    /// A language added after submission can be in a different state from the
    /// first one, so App Store Connect can refuse one and accept another.
    /// Stopping at the first refusal leaves the listing half written.
    @Test func keepsGoingWhenOneLanguageIsRefused() async throws {
        let conflict = #"{"errors":[{"status":"409","code":"STATE_ERROR","detail":"Not now."}]}"#
        let transport = StubTransport([
            .failure(409, conflict),
            .ok(#"{"data":{"type":"x","id":"v-de"}}"#)
        ])
        let pusher = try TextPusher(client: ASCClient.stubbed(transport: transport))

        let result = await pusher.push(
            plan([change(.description, locale: "en-US"), change(.description, locale: "de-DE")]),
            to: listing(locales: ["en-US", "de-DE"], version: ["description": "old"]),
            localInformation: information(AppInformation.Fields(description: "One"))
                .merging(information(AppInformation.Fields(description: "Zwei"), locale: "de-DE")) { first, _ in first }
        )

        #expect(result.written == ["de-DE"])
        #expect(result.failed.map(\.locale) == ["en-US"])
        #expect(result.isCompleteSuccess == false)
    }

    @Test func saysWhichLanguageFailedAndWhy() async throws {
        let forbidden = #"{"errors":[{"status":"403","code":"FORBIDDEN_ERROR"}]}"#
        let pusher = try TextPusher(client: ASCClient.stubbed(transport: StubTransport(.failure(403, forbidden))))

        let result = await pusher.push(
            plan([change(.description)]),
            to: listing(version: ["description": "old"]),
            localInformation: information(AppInformation.Fields(description: "One"))
        )

        let failure = try #require(result.failed.first)
        #expect(failure.locale == "en-US")
        #expect(failure.message.contains("App Manager"), "the role is the usual cause of a 403")
    }

    /// Trying to write a name with no editable app information would be a 409.
    /// Saying so plainly is better than passing it on.
    @Test func refusesTheNameWhenTheAppInformationIsNotEditable() async throws {
        let pusher = try TextPusher(client: ASCClient.stubbed(transport: StubTransport([])))

        let result = await pusher.push(
            plan([change(.name)]),
            to: listing(appInfoID: nil),
            localInformation: information(AppInformation.Fields(name: "Demo"))
        )

        #expect(result.written.isEmpty)
        #expect(result.failed.first?.message.contains("Prepare for Submission") == true)
    }

    // MARK: - Nothing to do

    @Test func writesNothingForAnEmptyPlan() async throws {
        let transport = StubTransport([])
        let pusher = try TextPusher(client: ASCClient.stubbed(transport: transport))

        let result = await pusher.push(plan([]), to: listing(), localInformation: [:])

        #expect(result.written.isEmpty)
        #expect(result.failed.isEmpty)
        #expect(await transport.requestCount == 0)
    }

    @Test func reportsEachLanguageAsItGoes() async throws {
        let transport = StubTransport([
            .ok(#"{"data":{"type":"x","id":"a"}}"#),
            .ok(#"{"data":{"type":"x","id":"b"}}"#)
        ])
        let pusher = try TextPusher(client: ASCClient.stubbed(transport: transport))

        let reported = Reported()
        _ = await pusher.push(
            plan([change(.description, locale: "en-US"), change(.description, locale: "de-DE")]),
            to: listing(version: ["description": "old"]),
            localInformation: information(AppInformation.Fields(description: "One"))
                .merging(information(AppInformation.Fields(description: "Zwei"), locale: "de-DE")) { first, _ in first },
            progress: { reported.add($0) }
        )
        #expect(reported.locales == ["en-US", "de-DE"])
    }
}

/// The progress callback runs on whatever is pushing, so collecting from it
/// needs somewhere safe to put the results.
private final class Reported: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    func add(_ locale: String) {
        lock.lock()
        defer { lock.unlock() }
        storage.append(locale)
    }

    var locales: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

/// A group of fields goes to App Store Connect in one request, so one field it
/// refuses would otherwise take the acceptable ones down with it.
struct RefusedFieldTests {
    let pusher = TextPusherTests()

    /// The wording Apple actually returned when whatsNew was sent on a first
    /// version, alongside a promotional text it would have accepted.
    static let whatsNewRefused = """
    {"errors":[{"status":"409","code":"STATE_ERROR",
      "detail":"Attribute 'whatsNew' cannot be edited at this time.",
      "source":{"pointer":"/data/attributes/whatsNew"}}]}
    """

    @Test func readsTheFieldFromTheSourcePointer() {
        let error = ASCError.conflict(details: [
            ASCErrorDetail(code: "STATE_ERROR", pointer: "/data/attributes/whatsNew")
        ])
        #expect(TextPusher.refusedFields(in: error) == [.whatsNew])
    }

    @Test func readsTheFieldFromTheWordingWhenThereIsNoPointer() {
        let error = ASCError.conflict(details: [
            ASCErrorDetail(code: "STATE_ERROR", detail: "Attribute 'whatsNew' cannot be edited at this time.")
        ])
        #expect(TextPusher.refusedFields(in: error) == [.whatsNew])
    }

    @Test func findsNoFieldInAnErrorThatNamesNone() {
        let error = ASCError.conflict(details: [
            ASCErrorDetail(code: "STATE_ERROR", detail: "This version cannot be edited.")
        ])
        #expect(TextPusher.refusedFields(in: error).isEmpty)
    }

    /// A 403 is about the key's role, not about one field, so nothing should be
    /// dropped and retried.
    @Test func findsNoFieldInAnErrorThatIsNotAConflict() {
        let error = ASCError.forbidden(details: [
            ASCErrorDetail(code: "FORBIDDEN_ERROR", detail: "Attribute 'whatsNew' something.")
        ])
        #expect(TextPusher.refusedFields(in: error).isEmpty)
    }

    // MARK: - Through a push

    /// The case that cost a real push: what's new was refused on a first
    /// version and took the promotional text with it.
    @Test func writesTheRestWhenOneFieldIsRefused() async throws {
        let transport = StubTransport([
            .failure(409, Self.whatsNewRefused),
            .ok(#"{"data":{"type":"appStoreVersionLocalizations","id":"v-en"}}"#)
        ])
        let client = try ASCClient.stubbed(transport: transport)

        let result = await TextPusher(client: client).push(
            pusher.plan([pusher.change(.whatsNew), pusher.change(.promotionalText)]),
            to: pusher.listing(version: ["description": "old"]),
            localInformation: pusher.information(AppInformation.Fields(
                promotionalText: "New this week",
                whatsNew: "First release."
            ))
        )

        #expect(result.written == ["en-US"])
        #expect(result.failed.isEmpty)
        #expect(result.refused.map(\.field) == [.whatsNew])

        // The retry carries the acceptable field and leaves out the refused one.
        let retry = try #require(await transport.request(at: 1).httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: retry) as? [String: Any])
        let attributes = try #require((json["data"] as? [String: Any])?["attributes"] as? [String: Any])

        #expect(attributes["promotionalText"] as? String == "New this week")
        #expect(attributes["whatsNew"] == nil)
    }

    /// With nothing left to send there is nothing to retry, but it is still a
    /// named refusal rather than an unexplained failure. Saying which field it
    /// was is the whole point of recording it.
    @Test func recordsARefusalEvenWhenItWasTheOnlyField() async throws {
        let transport = StubTransport(.failure(409, Self.whatsNewRefused))
        let client = try ASCClient.stubbed(transport: transport)

        let result = await TextPusher(client: client).push(
            pusher.plan([pusher.change(.whatsNew)]),
            to: pusher.listing(version: ["description": "old"]),
            localInformation: pusher.information(AppInformation.Fields(whatsNew: "First release."))
        )

        #expect(result.refused.map(\.field) == [.whatsNew])
        #expect(result.failed.isEmpty, "it is refused, not unexplained")
        #expect(result.written.isEmpty, "nothing was written, so nothing is listed as written")
        #expect(result.isCompleteSuccess == false)
        #expect(await transport.requestCount == 1, "nothing to retry")
    }

    /// The reason travels with the refusal, in App Store Connect's own words.
    @Test func keepsTheWordsAppStoreConnectUsed() async throws {
        let client = try ASCClient.stubbed(
            transport: StubTransport(.failure(409, Self.whatsNewRefused))
        )

        let result = await client.pushingWhatsNew(with: pusher)
        let refusal = try #require(result.refused.first)
        #expect(refusal.reason.contains("cannot be edited at this time"))
    }

    /// An error naming no field is not a per-field problem, so retrying without
    /// something would be guessing.
    @Test func doesNotRetryAnErrorThatNamesNoField() async throws {
        let generic = #"{"errors":[{"status":"409","code":"STATE_ERROR","detail":"Not now."}]}"#
        let transport = StubTransport(.failure(409, generic))
        let client = try ASCClient.stubbed(transport: transport)

        let result = await TextPusher(client: client).push(
            pusher.plan([pusher.change(.whatsNew), pusher.change(.promotionalText)]),
            to: pusher.listing(version: ["description": "old"]),
            localInformation: pusher.information(AppInformation.Fields(
                promotionalText: "New this week",
                whatsNew: "First release."
            ))
        )

        #expect(result.failed.count == 1)
        #expect(await transport.requestCount == 1)
    }

    @Test func saysNothingWasRefusedWhenEverythingWasTaken() async throws {
        let transport = StubTransport(.ok(#"{"data":{"type":"x","id":"v-en"}}"#))
        let client = try ASCClient.stubbed(transport: transport)

        let result = await TextPusher(client: client).push(
            pusher.plan([pusher.change(.promotionalText)]),
            to: pusher.listing(version: ["description": "old"]),
            localInformation: pusher.information(AppInformation.Fields(promotionalText: "New"))
        )

        #expect(result.refused.isEmpty)
        #expect(result.isCompleteSuccess)
    }
}

private extension ASCClient {
    func pushingWhatsNew(with pusher: TextPusherTests) async -> TextPusher.Result {
        await TextPusher(client: self).push(
            pusher.plan([pusher.change(.whatsNew)]),
            to: pusher.listing(version: ["description": "old"]),
            localInformation: pusher.information(AppInformation.Fields(whatsNew: "First release."))
        )
    }
}

struct PushErrorTests {
    /// A reason is a resource. Put straight into a Swift string, it prints as
    /// the struct and its key rather than as the sentence.
    @Test func listsEachBlockedReasonAsASentence() {
        let error = PushError.blocked([ChangePlan.Blocked(
            reason: "Version 1.0 is ready for sale and does not accept text changes.",
            affects: "3 text changes",
            cause: .versionStatus,
            parts: [.appInformation]
        )])

        #expect(error.description.contains("  Version 1.0 is ready for sale and does not accept text changes."))
        #expect(error.description.contains("LocalizedStringResource") == false)
    }
}
