import Foundation

/// What a check found.
public struct CheckResult: Sendable {
    /// The version that was checked. Nil when there was nothing to check.
    public let versionString: String?

    /// Everything wrong that is being shown. Silenced warnings are not in here.
    public let problems: [Problem]

    /// The warnings this version has, that somebody silenced. Kept whole rather
    /// than counted, so a person can read what they hid and change their mind.
    public let silenced: [Problem]

    /// Silenced warnings this version no longer has, from a file that was
    /// silenced and then fixed.
    public let staleSilences: [SilencedWarning]

    public var errors: [Problem] { problems.errors }
    public var warnings: [Problem] { problems.warnings }
    public var canPublish: Bool { problems.blocksPublishing == false }

    public init(
        versionString: String?,
        problems: [Problem],
        silenced: [Problem] = [],
        staleSilences: [SilencedWarning] = []
    ) {
        self.versionString = versionString
        self.problems = problems
        self.silenced = silenced
        self.staleSilences = staleSilences
    }
}

/// Runs every check a project can have run against it without a network
/// connection. The command line tool and the app both go through here, so what
/// one reports the other reports.
public enum Checker {
    /// Checks one version, or the newest one when none is named.
    ///
    /// A project with no versions yet is a state worth reporting rather than an
    /// error worth throwing: the app has to be able to open one and say so.
    public static func check(project: Project, version requested: String? = nil) throws -> CheckResult {
        let validator = Validator(project: project)
        let available = try project.versionNames()

        // With no version there is no content to check, so the configuration is
        // all there is. With one, `validate` covers the configuration too, and
        // running it here as well would report every configuration problem twice.
        // The Xcode project beside this one is what actually ships, so what it
        // says about the app is checked against what the listing says.
        let drift = XcodeDrift.problems(project: project, versions: available)

        // In-app purchases are not tied to a version, so they are checked
        // whether or not there is one to check against.
        let products = validator.validate(ProductStore.load(in: project))

        guard let version = try resolveVersion(requested, available: available, project: project) else {
            var problems = validator.validateConfiguration() + drift + products
            problems.append(Problem(
                severity: .warning,
                area: .layout,
                message: LocalizedStringResource("This project has no versions yet.", bundle: .here),
                fix: LocalizedStringResource("""
                Make \(project.config.versionsPath)/<version>/\(Project.informationFolderName) \
                and put an app information file in it.
                """, bundle: .here),
                path: project.config.versionsPath,
                kind: .noVersionsYet
            ))
            return CheckResult(versionString: nil, problems: problems.sortedForDisplay)
        }

        let content = try ContentStore.load(version: version, in: project)
        let problems = validator.validate(content) + drift + products
        let silenced = WarningSilence.readAll(version: version, in: project)

        let split = WarningSilence.split(problems, by: silenced)
        return CheckResult(
            versionString: version,
            problems: split.shown.sortedForDisplay,
            silenced: split.hidden.sortedForDisplay,
            staleSilences: WarningSilence.stale(silenced, against: problems)
        )
    }

    private static func resolveVersion(
        _ requested: String?,
        available: [String],
        project: Project
    ) throws -> String? {
        guard let requested else { return available.last }
        guard available.contains(requested) else { throw ProjectError.noSuchVersion(requested) }
        return requested
    }
}
