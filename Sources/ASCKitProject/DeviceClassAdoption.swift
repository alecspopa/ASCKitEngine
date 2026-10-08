import Foundation

/// Taking a device class the waiting screenshots name into a project.
///
/// A project lists the device classes it ships, and an image for any other one
/// is refused. That refusal is right the first time somebody drops an iPad
/// screenshot into an iPhone-only project by mistake. It is wrong the first
/// time an app starts shipping on iPad: the images are made, they are named,
/// they are the size Apple takes, and the only thing missing is a line in
/// `asckit.json`.
///
/// So the refusal carries the device class it refused, and this puts that
/// device class in the list. The inbox sheet and `asckit inbox --adopt-devices`
/// both come here, so a device class taken in from the window and one taken in
/// from the terminal leave the same project behind.
public enum DeviceClassAdoption {
    /// The device classes the waiting images name that this project does not
    /// list, in the order the images arrived.
    ///
    /// Reads no files, so a view can ask on every redraw and a button can carry
    /// the name of what it would add.
    public static func unlisted(in plan: Inbox.Plan) -> [DeviceClass] {
        var found: [DeviceClass] = []
        for refusal in plan.refusals {
            guard let deviceClass = refusal.unlistedDeviceClass else { continue }
            if found.contains(deviceClass) == false { found.append(deviceClass) }
        }
        return found
    }

    /// How many waiting images are held up by one of these device classes.
    public static func waitingCount(for deviceClasses: [DeviceClass], in plan: Inbox.Plan) -> Int {
        plan.refusals.filter { refusal in
            guard let deviceClass = refusal.unlistedDeviceClass else { return false }
            return deviceClasses.contains(deviceClass)
        }
        .count
    }

    // MARK: - Writing it

    /// What the adoption did.
    public struct Outcome: Sendable, Equatable {
        /// Device classes added to the list, by the name `asckit.json` uses.
        public var added: [String] = []

        /// Device classes that were already listed. Nothing was written for
        /// these.
        public var left: [String] = []

        /// The version whose screenshot folders were made, when the project has
        /// a version folder to make them in.
        public var version: String?

        /// The configuration as it now reads on disk.
        public var config: ProjectConfig
    }

    /// Adds each of these device classes to the list, and makes the folder its
    /// screenshots go in for every language.
    ///
    /// Writes over nothing. A device class already listed keeps its place, and
    /// a folder already there is left as it is.
    ///
    /// The configuration is written once, at the end, so a run that throws
    /// halfway leaves the list as it was. Pass the version the project is
    /// working on to get the folders as well; a project with no version folder
    /// yet still gets the list.
    @discardableResult
    public static func adopt(
        _ deviceClasses: [DeviceClass],
        version: String?,
        in project: Project
    ) throws -> Outcome {
        var config = project.config
        var outcome = Outcome(version: version, config: config)

        for deviceClass in deviceClasses {
            guard config.deviceClasses.contains(deviceClass.id) == false else {
                outcome.left.append(deviceClass.id)
                continue
            }
            config.deviceClasses.append(deviceClass.id)
            outcome.added.append(deviceClass.id)
        }

        guard outcome.added.isEmpty == false else { return outcome }

        // Appended rather than sorted in. The order of this list is the order
        // the device classes are shown in, and sorting would move one somebody
        // put where they wanted it.
        try project.write(config)
        outcome.config = config

        if let version {
            try makeScreenshotFolders(
                for: outcome.added, version: version, config: config, in: project
            )
        }
        return outcome
    }

    /// Takes a device class out of the list.
    ///
    /// The other half of `adopt`. A list written for an iPhone app that later
    /// became a Mac app names device classes App Store Connect takes nothing
    /// for, and this is how one of those leaves.
    ///
    /// Removes no files. The folders stay where they are, and the checker
    /// reports them as folders for a device class nobody lists, so nothing is
    /// lost by taking a line out and putting it back.
    @discardableResult
    public static func drop(_ deviceClass: DeviceClass, in project: Project) throws -> ProjectConfig {
        var config = project.config
        guard let index = config.deviceClasses.firstIndex(of: deviceClass.id) else { return config }

        config.deviceClasses.remove(at: index)
        config.usesSourceScreenshots = config.usesSourceScreenshots
            .mapValues { $0.filter { $0 != deviceClass.id } }
            .filter { $0.value.isEmpty == false }
        config.copiesScreenshotsFrom = config.copiesScreenshotsFrom
            .mapValues { $0.filter { $0.key != deviceClass.id } }
            .filter { $0.value.isEmpty == false }

        try project.write(config)
        return config
    }

    /// The folders this device class's screenshots go in, one per language the
    /// project ships.
    ///
    /// Made empty, for the reason `LocaleAdoption` makes them: somebody can
    /// then drop a screenshot into the right place in the Finder without
    /// building the path by hand.
    private static func makeScreenshotFolders(
        for deviceClassIDs: [String],
        version: String,
        config: ProjectConfig,
        in project: Project
    ) throws {
        for locale in config.writtenLocales {
            for deviceClassID in deviceClassIDs {
                try FileManager.default.createDirectory(
                    at: project.screenshotsURL(
                        version: version, locale: locale, deviceClassID: deviceClassID
                    ),
                    withIntermediateDirectories: true
                )
            }
        }
    }
}
