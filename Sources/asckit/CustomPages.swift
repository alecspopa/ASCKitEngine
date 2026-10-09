import ArgumentParser
import ASCKitAPI
import ASCKitProject
import Foundation

private let noPage = """
There is no custom product page on App Store Connect. Make one in App Store Connect first. \
ASCKit never makes one.
"""

// MARK: - Read

struct CustomPages: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "custom-pages",
        abstract: "Read the custom product pages, and make a folder for each.",
        discussion: """
        Reads the custom product pages from App Store Connect and writes nothing to it. For \
        each page whose version is in Prepare for Submission, it makes an empty folder in \
        \(CustomPageFolders.folderName)/ for each language, and a text file for each \
        language that has none.

        To change a page, edit \(CustomPageFolders.folderName)/<page>/text/<language>.json \
        and \(CustomPageFolders.folderName)/<page>/page.json, drop images in the language \
        folders, and run asckit push-custom-pages.

        An approved page takes no changes. Start a new version of it in App Store Connect, \
        then run this command again. ASCKit never makes a page, a version or a language of a page.
        """
    )

    @OptionGroup var options: ProjectOptions

    @Flag(name: .long, help: "Print what App Store Connect answers, with every id, and write nothing.")
    var raw = false

    func run() async throws {
        let project = try options.loadProject()

        if raw {
            try await CustomPageProbe.print(client: makeClient(for: project), bundleID: project.config.bundleID)
            return
        }

        let reading = try await makeSession(for: project).readCustomPages()
        guard reading.remote.pages.isEmpty == false else {
            print(noPage)
            return
        }

        CustomPageReport.print(reading)
        if reading.plan.hasChanges {
            print("")
            print("Run asckit push-custom-pages to write these.")
        }
    }
}

enum CustomPageReport {
    static func print(_ reading: PushSession.CustomPageReading) {
        let plan = reading.plan

        for page in reading.remote.pages {
            let state = page.version?.state?.rawValue ?? unknownState
            Swift.print("\(page.name), \(state)\(page.visible ? "" : ", hidden")")
            let locales = page.version?.localizations.map(\.locale) ?? []
            Swift.print("  languages: \(locales.isEmpty ? "none" : locales.joined(separator: ", "))")

            guard page.isEditable else {
                Swift.print("  takes no changes. Start a new version in App Store Connect.")
                continue
            }
            let lines = plan.lines(pageID: page.id)
            for line in lines {
                Swift.print("  \(line)")
            }
            if lines.isEmpty {
                Swift.print("  no changes")
            }
        }

        Swift.print("")
        Swift.print(plan.hasChanges ? "A push would write the changes above." : "A push would change nothing.")

        if plan.unplaced.isEmpty == false {
            Swift.print("")
            Swift.print("These folders hold images with no place to go:")
            for item in plan.unplaced {
                Swift.print("  \(CustomPageFolders.folderName)/\(item.slot.path), "
                    + "\(countedNoun(item.imageCount, "image")): \(reason(item.reason))")
            }
        }

        if reading.madeFolders.isEmpty == false {
            Swift.print("")
            Swift.print("Made \(countedNoun(reading.madeFolders.count, "empty folder")) in "
                + "\(CustomPageFolders.folderName)/. Drop the images in them.")
        }
        if reading.seededFiles.isEmpty == false {
            Swift.print("Wrote \(countedNoun(reading.seededFiles.count, "file")) with what App Store Connect holds.")
        }
    }

    static func reason(_ reason: CustomPagePlan.Unplaced.Reason) -> String {
        switch reason {
        case .noPage: "no page has this name. It was removed, or it never existed."
        case .locked: "the page is in review or approved. Start a new version in App Store Connect."
        case .noLanguage: "the page has no such language. Add it in App Store Connect."
        case .deviceClassNotListed: "this project does not list the device class."
        }
    }
}

// MARK: - Push

struct PushCustomPages: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "push-custom-pages",
        abstract: "Write the custom product pages: deep links, promotional text, keywords and images.",
        discussion: """
        Run asckit custom-pages first to make the folders and the text files.

        The words go first, then the images. The images go into the app's asset library, each \
        file once, and are placed on each page's languages. An empty image folder leaves the \
        page's images as they are.

        The page still needs review. Send it in App Store Connect.
        """
    )

    @OptionGroup var options: ProjectOptions

    @Flag(name: .long, help: "Do not ask. Use only for a plan you have already read.")
    var yes = false

    func run() async throws {
        let project = try options.loadProject()
        let session = try makeSession(for: project)
        let reading = try await session.readCustomPages()

        guard reading.remote.pages.isEmpty == false else {
            print(noPage)
            return
        }

        let problems = Validator(project: project)
            .validate(reading.content, keywords: reading.remote.keywords)
            .filter { $0.severity == .error }
        try stopOnErrors(problems, project: project)

        CustomPageReport.print(reading)
        guard reading.plan.hasChanges else { return }

        guard confirmed(yes: yes, "Write these to App Store Connect?") else {
            throw ExitCode.failure
        }

        var succeeded = true
        if reading.plan.hasTextChanges {
            let outcome = await session.pushCustomPageText(reading) { print("  \($0)") }
            print("")
            if outcome.result.written.isEmpty == false {
                print("Wrote: \(outcome.result.written.joined(separator: ", "))")
            }
            for failure in outcome.result.failed {
                print("Failed, \(failure.label): \(failure.message)")
            }
            reportReceipt(outcome, project: project)
            succeeded = succeeded && outcome.result.isCompleteSuccess
        }

        if reading.plan.hasImageChanges {
            let outcome = await session.pushCustomPageImages(reading) { print("  \($0.label)") }
            reportImages(outcome.result, readBack: "Run asckit custom-pages to read it back.")
            reportReceipt(outcome, project: project)
            succeeded = succeeded && outcome.result.isCompleteSuccess
        }

        if succeeded == false { throw ExitCode.failure }
    }
}

// MARK: - Raw

/// What App Store Connect says about the pages, with the ids, so a person can
/// see what a keyword id looks like and which placements a page takes.
enum CustomPageProbe {
    static func print(client: ASCClient, bundleID: String) async throws {
        let remote = try await client.customPages(bundleID: bundleID)
        Swift.print("app \(remote.appID)")

        for page in try await client.customPages(appID: remote.appID) {
            let attributes = page.attributes
            Swift.print("")
            Swift.print("page \(page.id) \"\(attributes?.name ?? "")\" visible=\(attributes?.visible.map(String.init) ?? "nil")")
            Swift.print("  url \(attributes?.url ?? "nil")")
            for version in try await client.customPageVersions(pageID: page.id) {
                let state = version.attributes?.state?.rawValue ?? unknownState
                Swift.print("  version \(version.id) \(version.attributes?.version ?? "nil") \(state)"
                    + " deepLink=\(version.attributes?.deepLink ?? "nil")")
            }
            guard let shown = remote.page(id: page.id)?.version else { continue }
            Swift.print("  shown version \(shown.id)")
            for localization in shown.localizations {
                Swift.print("    \(localization.locale) \(localization.id)")
                Swift.print("      promotionalText: \(localization.promotionalText ?? "nil")")
                Swift.print("      keywords: \(localization.keywordIDs)")
                for placement in localization.placements {
                    Swift.print("      placement \(placement.type?.rawValue ?? "nil") \(placement.group ?? "nil")")
                }
            }
        }

        Swift.print("")
        for (locale, keywords) in remote.keywords.sorted(by: { $0.key < $1.key }) {
            Swift.print("app keywords \(locale): \(keywords)")
        }

        try await printVersionKeywords(client: client, appID: remote.appID)
        try await printRefData(client: client)
    }

    private static func printVersionKeywords(client: ASCClient, appID: String) async throws {
        for version in try await client.appStoreVersions(appID: appID, platform: .ios) {
            let string = version.attributes?.versionString ?? "nil"
            let state = version.attributes?.appVersionState?.rawValue ?? unknownState
            Swift.print("")
            Swift.print("version \(string) \(state)")
            for localization in try await client.versionLocalizations(versionID: version.id) {
                let locale = localization.attributes?.locale ?? "nil"
                let keywords = try await client.versionKeywordIDs(localizationID: localization.id)
                Swift.print("  \(locale) text: \(localization.attributes?.keywords ?? "nil")")
                Swift.print("  \(locale) ids: \(keywords)")
            }
        }
    }

    private static func printRefData(client: ASCClient) async throws {
        let refData = try await client.assetLibraryRefData()
        Swift.print("")
        Swift.print("features: \(refData.features.map(\.featureId))")
        for feature in refData.features where feature.featureId.contains("CUSTOM") {
            Swift.print("feature \(feature.featureId)")
            for policy in feature.placementPolicies ?? [] {
                let limits = (policy.groupLimits ?? []).map {
                    "\($0.groupIds ?? []) max \($0.maxCount.map(String.init) ?? "nil")"
                }
                Swift.print("  \(policy.placementType.rawValue): \(limits)")
            }
        }
    }
}
