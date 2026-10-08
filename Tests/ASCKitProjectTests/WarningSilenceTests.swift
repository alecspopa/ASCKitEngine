import Foundation
import Testing
@testable import ASCKitProject

/// Silencing hides something somebody would otherwise be told, so the rules
/// about what it hides, for how long, and how to undo it have to be exact.
final class WarningSilenceTests {
    let fixture: FixtureProject

    init() throws {
        fixture = try FixtureProject()
        try fixture.writeConfig(ProjectConfig(
            bundleID: "com.example.Demo",
            keyID: "ABC123",
            issuerID: "issuer",
            sourceLocale: "en-US",
            locales: ["en-US", "de-DE"],
            deviceClasses: [DeviceClass.iPhone69.id]
        ))
    }

    deinit {
        fixture.remove()
    }

    /// A project with one warning in it and nothing else wrong: de-DE has a
    /// screenshot the source language does not.
    func writeAProjectWithAWarning() throws {
        try fixture.writeCopy(AppInformation(locale: "en-US", status: .approved, fields: .init(
            name: "Demo", subtitle: "A demo", keywords: "demo",
            description: "What it does.", supportUrl: "https://example.com"
        )))
        try fixture.writeCopy(AppInformation(locale: "de-DE", status: .approved, fields: .init(
            name: "Demo", subtitle: "Eine Demo", keywords: "demo",
            description: "Was es macht.", supportUrl: "https://example.com"
        )))

        for locale in ["en-US", "de-DE"] {
            try fixture.writeScreenshot(
                locale: locale, deviceClassID: DeviceClass.iPhone69.id,
                named: named("hero", position: 1, locale: locale), width: 1290, height: 2796
            )
        }
        // Only de-DE has this one, so nothing warns about it. The warning comes
        // from the other direction: en-US has one de-DE has not.
        try fixture.writeScreenshot(
            locale: "en-US", deviceClassID: DeviceClass.iPhone69.id,
            named: named("shared", position: 2, locale: "en-US"), width: 1290, height: 2796
        )
    }

    /// A subscription that does not say how long a period is. The warning is
    /// about an in-app purchase, so its silence goes in the products file.
    func writeAProductWithAWarning() throws {
        try fixture.writeGroup()
        try fixture.writeProduct(Product(
            productID: "com.example.pro.monthly",
            kind: Product.Kind.autoRenewableSubscription.rawValue,
            subscriptionGroup: "Pro",
            status: .approved,
            price: Product.PricePlan(baseTerritory: "USA", baseAmount: Money("4.99"), curve: "purchasing-power"),
            localizations: [
                "en-US": .init(name: "Pro Monthly", description: "Everything in Pro, monthly."),
                "de-DE": .init(name: "Pro Monatlich", description: "Alles in Pro, monatlich.")
            ]
        ))
    }

    /// The name this project's screenshots carry. Written out rather than
    /// typed, because a name ASCKit would not write is itself a warning.
    func named(_ imageName: String, position: Int, locale: String) -> String {
        ScreenshotNaming.fileName(
            position: position,
            imageName: imageName,
            deviceClass: .iPhone69,
            locale: locale,
            extension: "png"
        )
    }

    func silenceFileURL() throws -> URL {
        try WarningSilence.url(version: fixture.version, in: fixture.load())
    }

    /// What the file holds on disk. `WarningSilence.read` writes a broken file
    /// again, so it cannot tell what a check left there.
    func warningsOnDisk() throws -> [SilencedWarning] {
        struct Stored: Decodable { var warnings: [SilencedWarning] }
        return try JSONDecoder().decode(Stored.self, from: Data(contentsOf: silenceFileURL())).warnings
    }

    /// The warning these tests are about: de-DE is missing a screenshot the
    /// source language has. A real project warns about several things at once,
    /// so a test about one of them has to name the one it means.
    func missingScreenshotWarning(_ result: CheckResult) throws -> Problem {
        try #require(result.warnings.first { $0.area == .screenshots })
    }

    // MARK: - Silencing

    @Test func silencesAWarningAndStopsShowingIt() throws {
        try writeAProjectWithAWarning()
        let before = try fixture.check()
        let warning = try missingScreenshotWarning(before)

        try WarningSilence.silence([warning], version: fixture.version, in: fixture.load())

        let after = try fixture.check()
        #expect(after.warnings.contains(warning) == false)
        #expect(after.warnings.count == before.warnings.count - 1)
        #expect(after.silenced.map(\.message.english) == [warning.message.english])
    }

    /// The one somebody asks for when they have read the list and want it to
    /// stop asking about this version.
    @Test func silencesEveryWarningAVersionHas() throws {
        try writeAProjectWithAWarning()
        let before = try fixture.check()
        #expect(before.warnings.count > 1)

        try WarningSilence.silence(before.warnings, version: fixture.version, in: fixture.load())

        let after = try fixture.check()
        #expect(after.warnings.isEmpty)
        #expect(after.silenced.count == before.warnings.count)
    }

    /// An error is what App Store Connect refuses. A way to hide one would only
    /// be a way to find out later.
    @Test func refusesToSilenceAnError() throws {
        let error = Problem(
            severity: .error,
            area: .screenshots,
            message: "de-DE has no iPhone 6.9 inch screenshots.",
            locale: "de-DE",
            kind: .screenshotsMissing
        )
        let silenced = try WarningSilence.silence(
            [error], version: fixture.version, in: fixture.load()
        )

        #expect(silenced == 0)
        #expect(try FileManager.default.fileExists(atPath: silenceFileURL().path) == false)
    }

    @Test func silencesTheSameWarningOnlyOnce() throws {
        try writeAProjectWithAWarning()
        let warnings = try fixture.check().warnings

        try WarningSilence.silence(warnings, version: fixture.version, in: fixture.load())
        let again = try WarningSilence.silence(warnings, version: fixture.version, in: fixture.load())

        #expect(again == 0)
        #expect(try WarningSilence.read(version: fixture.version, in: fixture.load())
            .count == warnings.count)
    }

    /// A silence is kept by the rule, not by the words. The words are
    /// translated and edited, and a silence that came back on either would be
    /// a decision lost for no reason a person could see.
    ///
    /// The cost is here on purpose: a count inside the message can change and
    /// the warning stays hidden.
    @Test func keepsAWarningSilencedWhenItsMessageChanges() throws {
        try writeAProjectWithAWarning()
        try WarningSilence.silence(
            fixture.check().warnings, version: fixture.version, in: fixture.load()
        )
        #expect(try fixture.check().warnings.isEmpty)

        // A third screenshot in the source language, so the warning now names
        // two missing slugs rather than one.
        try fixture.writeScreenshot(
            locale: "en-US", deviceClassID: DeviceClass.iPhone69.id,
            named: named("widgets", position: 3, locale: "en-US"), width: 1290, height: 2796
        )

        let after = try fixture.check()
        #expect(after.warnings.isEmpty)
        #expect(after.silenced.contains { $0.kind == .screenshotsMissingSiblings })
        #expect(after.staleSilences.isEmpty)
    }

    // MARK: - Reading what is silenced

    @Test func writesAnEmptyFileWhenThereIsNone() throws {
        try writeAProjectWithAWarning()

        #expect(try WarningSilence.read(version: fixture.version, in: fixture.load()).isEmpty)
        #expect(try warningsOnDisk().isEmpty)
    }

    /// A folder that a read made would show as a version, or as products in a
    /// project that sells none.
    @Test func makesNoFolderForTheFile() throws {
        let project = try fixture.load()

        #expect(WarningSilence.read(version: "9.9", in: project).isEmpty)
        #expect(WarningSilence.readProducts(in: project).isEmpty)
        #expect(FileManager.default.fileExists(atPath: project.versionURL("9.9").path) == false)
        #expect(FileManager.default.fileExists(atPath: project.productsURL.path) == false)
    }

    /// The second one is a file from before a silence kept its rule.
    @Test(arguments: [
        "not json",
        #"{"warnings": [{"area": "appInformation", "message": "de-DE has no whatsNew."}]}"#
    ])
    func writesTheFileAgainWhenItCannotBeRead(contents: String) throws {
        try writeAProjectWithAWarning()
        try Data(contents.utf8).write(to: silenceFileURL())

        let result = try fixture.check()

        #expect(result.problems.contains { $0.path?.hasSuffix(WarningSilence.fileName) == true } == false)
        #expect(result.silenced.isEmpty)
        #expect(try warningsOnDisk().isEmpty)
    }

    /// A warning somebody silenced and then fixed leaves its silence behind.
    /// Nothing removes it on its own, because a check changes no silence that
    /// it can read.
    @Test func namesASilenceForAWarningThatIsGone() throws {
        try writeAProjectWithAWarning()
        try WarningSilence.silence(
            [missingScreenshotWarning(fixture.check())],
            version: fixture.version,
            in: fixture.load()
        )

        // The missing screenshot arrives, so the warning it was silenced for is
        // no longer there.
        try fixture.writeScreenshot(
            locale: "de-DE", deviceClassID: DeviceClass.iPhone69.id,
            named: "02-shared.png", width: 1290, height: 2796
        )

        let result = try fixture.check()
        #expect(result.silenced.isEmpty)
        #expect(result.staleSilences.count == 1)
    }

    // MARK: - Bringing them back

    @Test func showsOneWarningAgain() throws {
        try writeAProjectWithAWarning()
        let before = try fixture.check()
        let warning = try missingScreenshotWarning(before)
        try WarningSilence.silence(before.warnings, version: fixture.version, in: fixture.load())

        let shown = try WarningSilence.show(
            [SilencedWarning(silencing: warning)], version: fixture.version, in: fixture.load()
        )

        let after = try fixture.check()
        #expect(shown == 1)
        #expect(after.warnings.map(\.message.english) == [warning.message.english])
        #expect(after.silenced.count == before.warnings.count - 1)
    }

    /// The file stays, because the next check would only write it again.
    @Test func emptiesTheFileWhenTheLastWarningComesBack() throws {
        try writeAProjectWithAWarning()
        try WarningSilence.silence(
            fixture.check().warnings, version: fixture.version, in: fixture.load()
        )
        #expect(try warningsOnDisk().isEmpty == false)

        let shown = try WarningSilence.showAll(version: fixture.version, in: fixture.load())
        #expect(try warningsOnDisk().isEmpty)

        let back = try fixture.check().warnings.count
        #expect(shown == back)
    }

    // MARK: - One version at a time

    /// The next version shows every listing warning again, because a decision
    /// about 1.0 says nothing about what 1.1 ships.
    @Test func silencesInOneVersionOnly() throws {
        try writeAProjectWithAWarning()
        try WarningSilence.silence(
            fixture.check().warnings, version: fixture.version, in: fixture.load()
        )

        let next = FixtureProject.at(fixture.rootURL, version: "1.1")
        try next.writeCopy(AppInformation(locale: "en-US", status: .approved))

        #expect(try WarningSilence.read(version: "1.1", in: fixture.load()).isEmpty)
    }

    /// The same words in 1.1 make the same text warning, and it shows again.
    /// `hidesAProductWarningInTheNextVersionToo` is the in-app purchase half.
    @Test func showsATextWarningAgainInTheNextVersion() throws {
        try writeAProjectWithAWarning()
        let text = try #require(fixture.check().warnings.first { $0.kind == .textMatchesSource })
        try WarningSilence.silence([text], version: fixture.version, in: fixture.load())

        let next = FixtureProject.at(fixture.rootURL, version: "1.1")
        for copy in try ContentStore.load(version: fixture.version, in: fixture.load()).appInformation.values {
            try next.writeCopy(copy)
        }

        let after = try fixture.check(version: "1.1")
        #expect(after.warnings.contains { $0.kind == .textMatchesSource && $0.locale == text.locale && $0.field == text.field })
        #expect(after.silenced.isEmpty)
    }

    @Test func writesTheFileBesideTheVersionItIsAbout() throws {
        try writeAProjectWithAWarning()
        try WarningSilence.silence(
            fixture.check().warnings, version: fixture.version, in: fixture.load()
        )

        let url = try silenceFileURL()
        #expect(url.lastPathComponent == "silenced.json")
        #expect(url.deletingLastPathComponent().lastPathComponent == fixture.version)
    }

    // MARK: - Warnings about in-app purchases

    /// One call can take both kinds of warning, and each silence goes in its
    /// own file.
    @Test func putsAProductSilenceInTheProductsFile() throws {
        try writeAProjectWithAWarning()
        try writeAProductWithAWarning()
        let warnings = try fixture.check().warnings

        let files = try WarningSilence.silenceByFile(warnings, version: fixture.version, in: fixture.load())

        #expect(files.map(\.location) == [.version(fixture.version), .products])
        #expect(files.last?.warnings.map(\.kind) == [.subscriptionHasNoPeriod])
        #expect(files.map(\.warnings.count).reduce(0, +) == warnings.count)
    }

    /// `asckit silence` numbers its list in this order, and `--show` takes a
    /// number off the same list.
    @Test func listsTheVersionSilencesBeforeTheProductSilences() throws {
        try writeAProjectWithAWarning()
        try writeAProductWithAWarning()
        try WarningSilence.silence(fixture.check().warnings, version: fixture.version, in: fixture.load())

        let files = try WarningSilence.readByFile(version: fixture.version, in: fixture.load())
        let list = try WarningSilence.readAll(version: fixture.version, in: fixture.load())

        #expect(files.map(\.location) == [.version(fixture.version), .products])
        #expect(list == files.flatMap(\.warnings))
        #expect(list.last?.kind == .subscriptionHasNoPeriod)
    }

    /// The last number in the list is the product warning. Its silence is in
    /// the products file, and the warning still comes back.
    @Test func showsAProductWarningAgainByItsNumber() throws {
        try writeAProjectWithAWarning()
        try writeAProductWithAWarning()
        let before = try fixture.check()
        try WarningSilence.silence(before.warnings, version: fixture.version, in: fixture.load())

        let list = try WarningSilence.readAll(version: fixture.version, in: fixture.load())
        let last = try #require(list.last)
        let shown = try WarningSilence.show([last], version: fixture.version, in: fixture.load())

        let after = try fixture.check()
        #expect(shown == 1)
        #expect(after.warnings.map(\.kind) == [.subscriptionHasNoPeriod])
        #expect(after.silenced.count == before.warnings.count - 1)
    }

    /// `--clear` empties both files, so the product warnings come back with the
    /// rest.
    @Test func bringsTheProductWarningsBackWithTheRest() throws {
        try writeAProjectWithAWarning()
        try writeAProductWithAWarning()
        let warnings = try fixture.check().warnings
        try WarningSilence.silence(warnings, version: fixture.version, in: fixture.load())

        let files = try WarningSilence.showAllByFile(version: fixture.version, in: fixture.load())

        #expect(files.map(\.location) == [.version(fixture.version), .products])
        #expect(try fixture.check().warnings.count == warnings.count)
        #expect(try WarningSilence.readProducts(in: fixture.load()).isEmpty)
    }

    /// A product belongs to no version. So its silence still hides the warning
    /// in the next version.
    @Test func hidesAProductWarningInTheNextVersionToo() throws {
        try writeAProjectWithAWarning()
        try writeAProductWithAWarning()
        let warning = try #require(fixture.check().warnings.first { $0.kind == .subscriptionHasNoPeriod })
        try WarningSilence.silence([warning], version: fixture.version, in: fixture.load())

        let next = FixtureProject.at(fixture.rootURL, version: "1.1")
        try next.writeCopy(AppInformation(locale: "en-US", status: .approved))

        let result = try fixture.check(version: "1.1")
        #expect(result.warnings.contains { $0.kind == .subscriptionHasNoPeriod } == false)
        #expect(result.silenced.map(\.kind) == [.subscriptionHasNoPeriod])
    }

    // MARK: - What the command says

    /// The test runs with one warning and with two. So each sentence uses both
    /// plural forms from the catalog.
    @Test(arguments: zip([1, 2], [
        [
            "Silenced 1 warning in 1.0. It is in versions/1.0/silenced.json.",
            "Silenced 1 warning in every version. It is in products/silenced.json.",
            "1 warning shows again in 1.0.",
            "1 warning shows again in every version."
        ],
        [
            "Silenced 2 warnings in 1.0. They are in versions/1.0/silenced.json.",
            "Silenced 2 warnings in every version. They are in products/silenced.json.",
            "2 warnings show again in 1.0.",
            "2 warnings show again in every version."
        ]
    ]))
    func namesTheFileAndCountsTheWarnings(count: Int, sentences: [String]) throws {
        let project = try fixture.load()
        let warning = SilencedWarning(silencing: Problem(
            severity: .warning,
            area: .products,
            message: "com.example.pro.monthly is a subscription and does not say how long a period is.",
            productID: "com.example.pro.monthly",
            kind: .subscriptionHasNoPeriod
        ))
        let files = [WarningSilence.Location.version("1.0"), .products].map {
            WarningSilence.File(location: $0, warnings: Array(repeating: warning, count: count))
        }

        let silenced = files.map { $0.silencedSentence(in: project).english }
        #expect(silenced + files.map(\.shownSentence.english) == sentences)
    }
}
