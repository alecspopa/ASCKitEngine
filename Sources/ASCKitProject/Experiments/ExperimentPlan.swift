import ASCKitAPI
import Foundation

/// What a push of the images of the draft tests would do.
///
/// Kept apart from `ChangePlan`. A test belongs to no version, so it has no
/// version state and no version folder, and it is read and pushed without
/// either.
public struct ExperimentPlan: Sendable {
    public struct SetPlan: Sendable, Identifiable {
        public let experimentID: String
        public let experimentName: String
        public let treatmentID: String
        public let treatmentName: String
        public let locale: String
        public let treatmentLocalizationID: String
        public let deviceClass: DeviceClass
        public let localFiles: [ScreenshotFile]

        /// How the slot compares in the App Asset Library.
        public let library: LibrarySlot

        public var id: String { "\(treatmentID)|\(locale)|\(deviceClass.id)" }
        public var action: ChangePlan.ScreenshotPlan.Action { LibraryPlanner.action(for: library) }
        public var changesAnything: Bool { library.isUnchanged == false }
        public var remoteCount: Int { library.current.count }

        /// One line saying where the set is, for a step or a failure.
        public var label: String { "\(experimentName) / \(treatmentName) / \(locale)" }
    }

    /// A folder of images with no place to go.
    public struct Unplaced: Sendable, Hashable, Identifiable {
        public enum Reason: Sendable, Hashable {
            /// No draft test has this name. It is finished, or never existed.
            case noDraftExperiment
            case noTreatment
            /// The treatment has no page for this language on App Store
            /// Connect, and ASCKit never makes one.
            case noLanguage
            case deviceClassNotListed
        }

        public let slot: ExperimentSlot
        public let imageCount: Int
        public let reason: Reason
        public var id: String {
            "\(slot.experiment)|\(slot.treatment)|\(slot.locale)|\(slot.deviceClassID)"
        }
    }

    /// The app previews of one device class in one language of a treatment.
    public struct PreviewSetPlan: Sendable, Identifiable {
        public let experimentName: String
        public let treatmentID: String
        public let treatmentName: String
        public let locale: String
        public let treatmentLocalizationID: String
        public let deviceClass: DeviceClass
        public let localFiles: [PreviewFile]
        public let library: LibrarySlot

        public var id: String { "\(treatmentID)|\(locale)|\(deviceClass.id)|previews" }
        public var changesAnything: Bool { library.isUnchanged == false }
        public var action: ChangePlan.ScreenshotPlan.Action { LibraryPlanner.action(for: library) }
        public var label: String { "\(experimentName) / \(treatmentName) / \(locale)" }
    }

    public let sets: [SetPlan]
    public let unplaced: [Unplaced]

    /// The header or search results art of one language of a treatment.
    public struct CreativeSetPlan: Sendable, Identifiable {
        public let treatmentID: String
        public let label: String
        public let treatmentLocalizationID: String
        public let plan: CreativePlan

        public var id: String { "\(treatmentLocalizationID)|\(plan.role.rawValue)" }
    }

    /// Only through the App Asset Library, so empty without a record.
    public let previewSets: [PreviewSetPlan]
    public let creativeSets: [CreativeSetPlan]

    public init(
        sets: [SetPlan],
        unplaced: [Unplaced],
        previewSets: [PreviewSetPlan] = [],
        creativeSets: [CreativeSetPlan] = []
    ) {
        self.sets = sets
        self.unplaced = unplaced
        self.previewSets = previewSets
        self.creativeSets = creativeSets
    }

    public var changingSets: [SetPlan] { sets.filter(\.changesAnything) }

    /// One line for each preview set and each piece of art that changes in a
    /// treatment, for a terminal. English, because a terminal reads it.
    public func libraryLines(treatmentID: String) -> [String] {
        let previews = previewSets.filter { $0.treatmentID == treatmentID && $0.changesAnything }.map { item in
            "\(item.locale)/\(item.deviceClass.id) previews: \(Self.describe(item.library))"
        }
        let art = creativeSets.filter { $0.treatmentID == treatmentID && $0.plan.changesAnything }.map { item in
            let locale = item.plan.locale
            return switch (item.plan.file, item.plan.usesHeader) {
            case (nil, _): "\(locale) \(item.plan.role.rawValue): will be removed"
            case (_?, true): "\(locale) \(item.plan.role.rawValue): show the header"
            case let (file?, false): "\(locale) \(item.plan.role.rawValue): put up \(file.fileName)"
            }
        }
        return previews + art
    }

    static func describe(_ slot: LibrarySlot) -> String {
        if slot.toRemove.isEmpty, slot.placementsToAdd == 0 {
            return slot.posterFrames.isEmpty ? "change the order" : "change the poster frame"
        }
        return "remove \(slot.toRemove.count), add \(slot.placementsToAdd)"
    }

    public var changingPreviewSets: [PreviewSetPlan] { previewSets.filter(\.changesAnything) }
    public var hasChanges: Bool {
        sets.contains(where: \.changesAnything) || previewSets.contains(where: \.changesAnything)
            || creativeSets.contains(where: \.plan.changesAnything)
    }

    public var imagesToAdd: Int {
        sets.reduce(0) { total, item in
            guard case let .replace(_, adding) = item.action else { return total }
            return total + adding
        }
    }

    public var imagesToRemove: Int {
        sets.reduce(0) { total, item in
            guard case let .replace(removing, _) = item.action else { return total }
            return total + removing
        }
    }
}
