import Foundation

/// Where the listing and the Xcode project have stopped agreeing.
///
/// The Xcode project is what actually ships. When it says version 1.1 and the
/// listing only has a 1.0 folder, the listing is about to describe the wrong
/// build. When it gains a language and the listing does not, the app appears in
/// a store nobody wrote words for.
///
/// Warnings, never errors. Xcode moving first is the normal way round, and a
/// person part way through a release should not be told their project is
/// broken for being part way through.
enum XcodeDrift {
    static func problems(project: Project, versions: [String]) -> [Problem] {
        guard
            let projectURL = XcodeProject.find(in: project.xcodeFolderURL),
            let xcode = try? XcodeProject.read(at: projectURL)
        else {
            return []
        }

        // A project building more than one app has no one answer for which
        // version this listing follows, so nothing is claimed about it.
        let app = xcode.apps.count == 1 ? xcode.apps[0] : nil

        return versionProblems(app: app, versions: versions, name: projectURL.lastPathComponent)
            + bundleProblems(app: app, config: project.config)
            + languageProblems(regions: xcode.knownRegions, config: project.config)
    }

    // MARK: - Version

    private static func versionProblems(
        app: XcodeProject.App?,
        versions: [String],
        name: String
    ) -> [Problem] {
        guard let version = app?.marketingVersion, versions.isEmpty == false else { return [] }
        guard versions.contains(version) == false else { return [] }

        return [Problem(
            severity: .warning,
            area: .layout,
            message: LocalizedStringResource("""
            \(name) builds version \(version), \
            but there is no version \(version) on App Store Connect.
            """, bundle: .here),
            fix: LocalizedStringResource("""
            Create version \(version) on App Store Connect, \
            then pull the updates from there.
            """, bundle: .here),
            path: "versions",
            kind: .versionFolderMissingForXcode
        )]
    }

    // MARK: - Bundle identifier

    /// The one thing here that is an error. A listing pushed against the wrong
    /// bundle identifier goes to a different app.
    private static func bundleProblems(app: XcodeProject.App?, config: ProjectConfig) -> [Problem] {
        guard let bundleID = app?.bundleID, bundleID != config.bundleID else { return [] }

        return [Problem(
            severity: .error,
            area: .configuration,
            message: LocalizedStringResource("Xcode builds \(bundleID), and this project pushes to \(config.bundleID).", bundle: .here),
            fix: LocalizedStringResource("Change bundleId, or open the folder holding the right Xcode project.", bundle: .here),
            path: Project.defaultConfigName,
            kind: .bundleIDMismatch
        )]
    }

    // MARK: - Languages

    private static func languageProblems(regions: [String], config: ProjectConfig) -> [Problem] {
        var problems: [Problem] = []
        let listed = Set(config.locales)

        for (region, outcome) in RegionMatch.outcomes(for: regions) {
            switch outcome {
            case let .one(code) where listed.contains(code) == false:
                problems.append(Problem(
                    severity: .warning,
                    area: .configuration,
                    message: LocalizedStringResource("The app is built in \(region), and the listing has no \(code).", bundle: .here),
                    fix: LocalizedStringResource("Add \(code) to locales, or take \(region) out of the Xcode project.", bundle: .here),
                    locale: code,
                    path: Project.defaultConfigName,
                    kind: .appRegionNotListed
                ))

            case let .several(codes) where listed.isDisjoint(with: codes):
                problems.append(Problem(
                    severity: .warning,
                    area: .configuration,
                    message: LocalizedStringResource("""
                    The app is built in \(region), and the listing has none of \
                    \(codes.joined(separator: ", ")).
                    """, bundle: .here),
                    fix: LocalizedStringResource("Add whichever of those the app is written for.", bundle: .here),
                    path: Project.defaultConfigName,
                    kind: .appRegionNoneListed
                ))

            default:
                break
            }
        }
        return problems
    }
}
