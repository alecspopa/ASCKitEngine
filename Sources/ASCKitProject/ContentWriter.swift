import ASCKitAPI
import Foundation

/// Writes a version folder. The mirror of `ContentStore`, which reads one.
///
/// Every check that would make App Store Connect refuse an image happens here,
/// before anything moves. A caller cannot get a wrong file into a slot by
/// asking nicely, and cannot get half a batch in either: a bad file in the list
/// stops the whole call.
public enum ContentWriter {
    // MARK: - A version folder

    /// Makes the folder for one version and returns it.
    ///
    /// The folder and nothing in it. `VersionSeed` fills it with what App
    /// Store Connect copied into the new version.
    ///
    /// Refuses a version that already has a folder, so this can never be the
    /// thing that stood on somebody's work.
    @discardableResult
    public static func createVersion(_ version: String, in project: Project) throws -> URL {
        let folder = project.versionURL(version)
        guard FileManager.default.fileExists(atPath: folder.path) == false else {
            throw ContentWriteError.versionAlreadyThere(version)
        }

        try FileManager.default.createDirectory(
            at: project.informationURL(version: version),
            withIntermediateDirectories: true
        )
        return folder
    }

    // MARK: - App information

    public static func writeAppInformation(
        _ information: AppInformation,
        version: String,
        in project: Project
    ) throws {
        let url = project.informationURL(version: version, locale: information.locale)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(information).write(to: url)
    }

    // MARK: - In-app purchases

    /// Writes one product file.
    ///
    /// There is no matching delete. A product id is permanent and is compiled
    /// into the shipping app, and App Store Connect cannot delete a purchase at
    /// all, only stop selling it. A tool that can remove one from a file is a
    /// tool that eventually does, from a typo.
    public static func writeProduct(_ product: Product, in project: Project) throws {
        if let reason = ProductStore.reasonToRefuse(productID: product.productID) {
            throw ContentWriteError.badProductID(product.productID, reason: reason)
        }

        let url = project.productURL(productID: product.productID)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(product).write(to: url)
    }

    public static func writeSubscriptionGroup(_ group: SubscriptionGroup, in project: Project) throws {
        if let reason = ProductStore.reasonToRefuse(groupName: group.referenceName) {
            throw ContentWriteError.badGroupName(group.referenceName, reason: reason)
        }

        let url = project.subscriptionGroupURL(name: group.referenceName)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(group).write(to: url)
    }

    // MARK: - Screenshots

    /// Puts images into a slot and renumbers it.
    ///
    /// `position` is where the first new image lands, counting from 1. Nil puts
    /// them at the end.
    @discardableResult
    public static func addScreenshots(
        from sourceURLs: [URL],
        locale: String,
        deviceClass: DeviceClass,
        version: String,
        at position: Int? = nil,
        in project: Project
    ) throws -> [ScreenshotFile] {
        try writeScreenshots(ScreenshotWriteRequest(
            sourceURLs: sourceURLs,
            locale: locale,
            deviceClass: deviceClass,
            version: version,
            position: position,
            replacingExisting: false
        ), in: project).files
    }

    /// Adds images to one language of one treatment of a draft test.
    ///
    /// Named and numbered by the same rule as a version's screenshots, so the
    /// name App Store Connect holds is the name on disk.
    @discardableResult
    public static func addExperimentScreenshots(
        from sourceURLs: [URL],
        slot: ExperimentSlot,
        deviceClass: DeviceClass,
        at position: Int? = nil,
        replacingExisting: Bool = false,
        in project: Project
    ) throws -> ScreenshotWriteOutcome {
        try writeScreenshots(ScreenshotWriteRequest(
            sourceURLs: sourceURLs,
            locale: slot.locale,
            deviceClass: deviceClass,
            version: "",
            position: position,
            replacingExisting: replacingExisting,
            directory: project.experimentURL(
                experiment: slot.experiment,
                treatment: slot.treatment,
                locale: slot.locale,
                deviceClassID: deviceClass.id
            )
        ), in: project)
    }

    /// Replaces screenshots with matching names, and keeps the rest of the set.
    ///
    /// Replaced files go to the Trash. Two files match when they show the same
    /// thing, which is the name with its number, device class, and language
    /// taken off.
    @discardableResult
    public static func replaceScreenshots(
        from sourceURLs: [URL],
        locale: String,
        deviceClass: DeviceClass,
        version: String,
        in project: Project
    ) throws -> ScreenshotWriteOutcome {
        try writeScreenshots(ScreenshotWriteRequest(
            sourceURLs: sourceURLs,
            locale: locale,
            deviceClass: deviceClass,
            version: version,
            position: nil,
            replacingExisting: true
        ), in: project)
    }

    /// Makes one slot hold exactly these files, in this order, and nothing else.
    ///
    /// Everything the slot held goes to the Trash, including files the new list
    /// has no name for. That is the promise a copy between two languages of one
    /// language needs: afterwards the two folders hold the same pictures in the
    /// same order, rather than the old set with some of it written over.
    ///
    /// The Trash rather than a delete, because the file may be the only copy of
    /// that artwork anybody has.
    @discardableResult
    public static func replaceSlot(
        with sourceURLs: [URL],
        locale: String,
        deviceClass: DeviceClass,
        version: String,
        in project: Project
    ) throws -> ScreenshotWriteOutcome {
        let directory = project.screenshotsURL(
            version: version,
            locale: locale,
            deviceClassID: deviceClass.id
        )
        let slotName = SlotName(locale: locale, deviceClass: deviceClass)

        // Counted against an empty slot, because the whole set is going.
        try checkRoom(adding: sourceURLs.count, to: 0, deviceClass: deviceClass)

        // Every file is checked before any file moves, so a batch with one bad
        // image leaves the slot exactly as it was.
        let refData = RefDataCache.load(in: project)
        for url in sourceURLs {
            try check(url, against: deviceClass, refData: refData)
        }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        // The copies land under hidden names, so nothing stands on a name the
        // old set still holds. `slot` skips hidden files, so the old set is
        // still the only thing it reports.
        var arriving: [(url: URL, name: String)] = []
        for source in sourceURLs {
            let landing = directory.appending(
                path: ".asckit-arriving-\(UUID().uuidString).\(source.pathExtension)"
            )
            try FileManager.default.copyItem(at: source, to: landing)
            arriving.append((landing, name(of: source.lastPathComponent, in: slotName)))
        }

        // Only once every copy is in the folder.
        var trashed: [URL] = []
        for file in slot(at: directory) {
            var landed: NSURL?
            try FileManager.default.trashItem(at: file.url, resultingItemURL: &landed)
            if let landed = landed as URL? { trashed.append(landed) }
        }

        try ScreenshotRenumbering.apply(ordered: arriving)
        return ScreenshotWriteOutcome(files: slot(at: directory), trashed: trashed)
    }

    /// The screenshots now in the set, and the replaced files in the Trash.
    public struct ScreenshotWriteOutcome: Sendable {
        public let files: [ScreenshotFile]
        public let trashed: [URL]
    }

    private struct ScreenshotWriteRequest {
        let sourceURLs: [URL]
        let locale: String
        let deviceClass: DeviceClass
        let version: String
        let position: Int?
        let replacingExisting: Bool

        /// The folder to write into, when it is not a version's own.
        var directory: URL?
    }

    private static func writeScreenshots(
        _ request: ScreenshotWriteRequest,
        in project: Project
    ) throws -> ScreenshotWriteOutcome {
        let directory = request.directory ?? project.screenshotsURL(
            version: request.version,
            locale: request.locale,
            deviceClassID: request.deviceClass.id
        )

        let slotName = SlotName(locale: request.locale, deviceClass: request.deviceClass)

        let existing = slot(at: directory)
        let sources = request.sourceURLs.map {
            (url: $0, name: name(of: $0.lastPathComponent, in: slotName))
        }
        let replacedCount = replacementCount(
            in: existing,
            for: sources.map(\.name),
            slotName: slotName,
            replacingExisting: request.replacingExisting
        )
        try checkRoom(
            adding: request.sourceURLs.count - replacedCount,
            to: existing.count,
            deviceClass: request.deviceClass
        )

        // Every file is checked before any file moves, so a batch with one bad
        // image leaves the slot exactly as it was.
        let refData = RefDataCache.load(in: project)
        for url in request.sourceURLs {
            try check(url, against: request.deviceClass, refData: refData)
        }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        // Landing names are hidden and unique. A file copied straight to its
        // real name would overwrite whatever already holds that number, and two
        // arriving files of one name would overwrite each other.
        var arriving: [(url: URL, name: String)] = []
        for source in sources {
            let landing = directory.appending(
                path: ".asckit-arriving-\(UUID().uuidString).\(source.url.pathExtension)"
            )
            try FileManager.default.copyItem(at: source.url, to: landing)
            arriving.append((landing, source.name))
        }

        var replaced: [ScreenshotFile] = []
        var remaining = arriving
        var ordered: [(url: URL, name: String)] = []
        for file in existing {
            let name = name(of: file.fileName, in: slotName)
            if request.replacingExisting, let index = remaining.firstIndex(where: { $0.name == name }) {
                ordered.append(remaining.remove(at: index))
                replaced.append(file)
            } else {
                ordered.append((file.url, name))
            }
        }

        let insertAt = min(max((request.position ?? ordered.count + 1) - 1, 0), ordered.count)
        ordered.insert(contentsOf: remaining, at: insertAt)

        var trashed: [URL] = []
        for file in replaced {
            var landed: NSURL?
            try FileManager.default.trashItem(at: file.url, resultingItemURL: &landed)
            if let landed = landed as URL? { trashed.append(landed) }
        }

        try ScreenshotRenumbering.apply(ordered: ordered)
        return ScreenshotWriteOutcome(files: slot(at: directory), trashed: trashed)
    }

    /// Puts a slot in the given order, named file by file.
    @discardableResult
    public static func reorderScreenshots(
        order: [String],
        locale: String,
        deviceClass: DeviceClass,
        version: String,
        in project: Project
    ) throws -> [ScreenshotFile] {
        let directory = project.screenshotsURL(
            version: version,
            locale: locale,
            deviceClassID: deviceClass.id
        )
        let existing = slot(at: directory)

        var remaining = existing
        var ordered: [ScreenshotFile] = []
        for name in order {
            guard let index = remaining.firstIndex(where: { matches($0, name: name) }) else {
                throw ContentWriteError.noSuchScreenshot(name: name, locale: locale, deviceClassID: deviceClass.id)
            }
            ordered.append(remaining.remove(at: index))
        }

        guard remaining.isEmpty else {
            throw ContentWriteError.incompleteOrder(missing: remaining.map(\.fileName))
        }

        try rename(ordered, locale: locale, deviceClass: deviceClass)
        return slot(at: directory)
    }

    /// Moves images to the Trash, then renumbers what is left.
    ///
    /// The Trash rather than a delete, because the caller may be a machine and
    /// the file may be the only copy of that artwork anybody has.
    @discardableResult
    public static func removeScreenshots(
        named names: [String],
        locale: String,
        deviceClass: DeviceClass,
        version: String,
        in project: Project
    ) throws -> [ScreenshotFile] {
        let directory = project.screenshotsURL(
            version: version,
            locale: locale,
            deviceClassID: deviceClass.id
        )
        let existing = slot(at: directory)

        var doomed: [ScreenshotFile] = []
        for name in names {
            guard let file = existing.first(where: { matches($0, name: name) }) else {
                throw ContentWriteError.noSuchScreenshot(name: name, locale: locale, deviceClassID: deviceClass.id)
            }
            doomed.append(file)
        }

        for file in doomed {
            try FileManager.default.trashItem(at: file.url, resultingItemURL: nil)
        }

        let kept = existing.filter { file in doomed.contains(file) == false }
        try rename(kept, locale: locale, deviceClass: deviceClass)
        return slot(at: directory)
    }

    // MARK: - Putting old names right

    /// Renames every screenshot in a version so that each one follows the
    /// naming rule, and says which files moved.
    ///
    /// A folder written before the rule holds shorter names. Adding or removing
    /// one image puts that whole set right, and this is for the sets nobody has
    /// touched since. Run it before a push: the name goes to App Store Connect
    /// with the image, and a set uploaded under the old names is a set the next
    /// push cannot match.
    @discardableResult
    public static func repairNames(
        version: String,
        in project: Project
    ) throws -> [(from: String, to: String)] {
        var moved: [(from: String, to: String)] = []

        for locale in project.config.writtenLocales {
            for deviceClass in project.config.resolvedDeviceClasses {
                let directory = project.screenshotsURL(
                    version: version,
                    locale: locale,
                    deviceClassID: deviceClass.id
                )
                let files = slot(at: directory)
                guard files.isEmpty == false else { continue }

                try rename(files, locale: locale, deviceClass: deviceClass)

                let after = slot(at: directory)
                for (before, now) in zip(files, after) where before.fileName != now.fileName {
                    moved.append((before.fileName, now.fileName))
                }
            }
        }
        return moved
    }

    private static func check(_ url: URL, against deviceClass: DeviceClass, refData: AssetLibraryRefData?) throws {
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw ContentWriteError.noSuchFile(url)
        }
        if let reason = reasonToRefuse(ImageInspector.inspect(url: url), for: deviceClass, refData: refData) {
            throw ContentWriteError.refusedImage(reason: reason)
        }
    }

    private static func checkRoom(adding count: Int, to existing: Int, deviceClass: DeviceClass) throws {
        let total = existing + count
        guard total <= DeviceClass.maximumScreenshotsPerSet else {
            throw ContentWriteError.tooManyScreenshots(
                deviceClassID: deviceClass.id,
                existing: existing,
                adding: count
            )
        }
    }

    private static func replacementCount(
        in existing: [ScreenshotFile],
        for incoming: [String],
        slotName: SlotName,
        replacingExisting: Bool
    ) -> Int {
        guard replacingExisting else { return 0 }

        var remaining = incoming
        var count = 0
        for file in existing {
            let name = name(of: file.fileName, in: slotName)
            guard let index = remaining.firstIndex(of: name) else { continue }
            remaining.remove(at: index)
            count += 1
        }
        return count
    }

    // MARK: - Naming

    /// The language and the device class one folder stands for.
    private struct SlotName {
        let locale: String
        let deviceClass: DeviceClass
    }

    /// What a file is called in this slot, without its number.
    ///
    /// A file already named by the rule keeps the name it came with, because
    /// this gives back what it already says. The folder is what decides, and
    /// two files disagree with it: one copied out of another language, and one
    /// filed before the rule existed. Both are put right here.
    private static func name(of fileName: String, in slotName: SlotName) -> String {
        ScreenshotNaming.tail(
            imageName: ScreenshotNaming.imageName(of: fileName),
            deviceClass: slotName.deviceClass,
            locale: slotName.locale
        )
    }

    /// Renumbers a slot and puts every name back under the rule.
    ///
    /// A file that arrived before this rule existed is renamed here, so one
    /// write is enough to make a folder agree with itself.
    private static func rename(
        _ files: [ScreenshotFile],
        locale: String,
        deviceClass: DeviceClass
    ) throws {
        let slotName = SlotName(locale: locale, deviceClass: deviceClass)
        try ScreenshotRenumbering.apply(
            ordered: files.map { (url: $0.url, name: name(of: $0.fileName, in: slotName)) }
        )
    }

    // MARK: - Reading a slot

    /// What is in a slot now, in the order the file names put it in.
    private static func slot(at directory: URL) -> [ScreenshotFile] {
        DirectoryListing.files(in: directory, keys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey])
            .map(ImageInspector.inspect)
    }

    /// A file is named in full. One name, one file, and no rule about which
    /// shortened forms also count.
    private static func matches(_ file: ScreenshotFile, name: String) -> Bool {
        file.fileName == name
    }
}

public enum ContentWriteError: Error, CustomLocalizedStringResourceConvertible {
    case versionAlreadyThere(String)
    case noSuchFile(URL)
    case refusedImage(reason: String)
    case tooManyScreenshots(deviceClassID: String, existing: Int, adding: Int)
    case noSuchScreenshot(name: String, locale: String, deviceClassID: String)
    case incompleteOrder(missing: [String])
    case badProductID(String, reason: String)
    case badGroupName(String, reason: String)

    public var localizedStringResource: LocalizedStringResource {
        switch self {
        case let .versionAlreadyThere(version):
            LocalizedStringResource("There is already a folder for version \(version).", bundle: .here)
        case let .noSuchFile(url):
            LocalizedStringResource("There is no file at \(url.path).", bundle: .here)
        case let .refusedImage(reason):
            LocalizedStringResource("\(reason)", bundle: .here)
        case let .tooManyScreenshots(deviceClassID, existing, adding):
            LocalizedStringResource("""
            \(deviceClassID) already holds \(existing) screenshots. Adding \(adding) would pass the \
            limit of \(DeviceClass.maximumScreenshotsPerSet). Remove some first.
            """, bundle: .here)
        case let .noSuchScreenshot(name, locale, deviceClassID):
            LocalizedStringResource("""
            There is no screenshot called \(name) in \(locale)/\(deviceClassID).
            """, bundle: .here)
        case let .incompleteOrder(missing):
            LocalizedStringResource("""
            The order left out \(missing.formatted(.list(type: .and, width: .narrow))). \
            Name every screenshot in the set.
            """, bundle: .here)
        case let .badProductID(productID, reason):
            LocalizedStringResource("\(productID) cannot be a product id. \(reason)", bundle: .here)
        case let .badGroupName(name, reason):
            LocalizedStringResource("\(name) cannot be a subscription group name. \(reason)", bundle: .here)
        }
    }
}

extension ContentWriteError: CustomStringConvertible {
    public var description: String { String(localized: localizedStringResource) }
}
