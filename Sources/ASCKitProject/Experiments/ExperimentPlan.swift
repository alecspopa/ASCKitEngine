import ASCKitAPI
import Foundation

/// What a push of the images of the draft tests would do.
///
/// Kept apart from `ChangePlan`. A test belongs to no version, so it has no
/// version state and no version folder, and it is read and pushed without
/// either.
public struct ExperimentPlan: Sendable {
    public struct SetPlan: LibrarySetPlan {
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
        public var remoteCount: Int { library.current.count }
        public var label: String { "\(experimentName) / \(treatmentName) / \(locale)" }
        public var slotName: String { deviceClass.id }
        public var parent: PlacementParent { .treatmentLocalization(id: treatmentLocalizationID) }
        public var libraryFiles: [LibraryFile] { localFiles.map(\.libraryFile) }
    }

    /// A folder of images with no place to go.
    public struct Unplaced: Sendable, Hashable, Identifiable {
        public enum Reason: Sendable, Hashable {
            /// No test that is not over has this name. It is finished, or
            /// never existed.
            case noDraftExperiment
            /// The test is in review, running, or another state that takes
            /// no change.
            case locked(state: ExperimentState?)
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
    public struct PreviewSetPlan: LibrarySetPlan {
        public let experimentName: String
        public let treatmentID: String
        public let treatmentName: String
        public let locale: String
        public let treatmentLocalizationID: String
        public let deviceClass: DeviceClass
        public let localFiles: [PreviewFile]
        public let library: LibrarySlot

        public var id: String { "\(treatmentID)|\(locale)|\(deviceClass.id)|previews" }
        public var label: String { "\(experimentName) / \(treatmentName) / \(locale)" }
        public var slotName: String { deviceClass.id }
        public var parent: PlacementParent { .treatmentLocalization(id: treatmentLocalizationID) }
        public var libraryFiles: [LibraryFile] { localFiles.map(\.libraryFile) }
    }

    public let sets: [SetPlan]
    public let unplaced: [Unplaced]

    /// The header or search results art of one language of a treatment.
    public struct CreativeSetPlan: LibrarySetPlan {
        public let treatmentID: String
        public let label: String
        public let treatmentLocalizationID: String
        public let plan: CreativePlan

        public var id: String { "\(treatmentLocalizationID)|\(plan.role.rawValue)" }
        public var slotName: String { plan.role.rawValue }
        public var parent: PlacementParent { .treatmentLocalization(id: treatmentLocalizationID) }
        public var libraryFiles: [LibraryFile] { plan.file.map { [$0.libraryFile] } ?? [] }
        public var library: LibrarySlot { plan.library }
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
            "\(item.locale)/\(item.deviceClass.id) previews: \(item.library.summary)"
        }
        let art = creativeSets.filter { $0.treatmentID == treatmentID && $0.changesAnything }.map(\.plan.summary)
        return previews + art
    }

    public var changingPreviewSets: [PreviewSetPlan] { previewSets.filter(\.changesAnything) }
    public var hasChanges: Bool {
        sets.contains(where: \.changesAnything) || previewSets.contains(where: \.changesAnything)
            || creativeSets.contains(where: \.changesAnything)
    }

    public var imagesToAdd: Int { sets.imagesToAdd }
    public var imagesToRemove: Int { sets.imagesToRemove }

    /// Every slot that changes, with the page each one goes on.
    var targets: [LibraryPusher.Target] {
        sets.changingTargets + previewSets.changingTargets + creativeSets.changingTargets
    }
}
