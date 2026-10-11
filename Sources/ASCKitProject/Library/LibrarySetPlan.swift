import ASCKitAPI
import Foundation

/// One slot of a plan that a push fills through the App Asset Library: the
/// screenshots, the previews or one piece of art of one language.
///
/// The plans of a version, a test and a custom page differ only in the
/// parent their placements go on and in the words of their label. So a push
/// target, a summary and a count are written once, here.
public protocol LibrarySetPlan: Sendable, Identifiable where ID == String {
    /// One line saying where the set is, for a step or a failure.
    var label: String { get }

    /// The device class, or the art role, that the slot belongs to.
    var slotName: String { get }

    var parent: PlacementParent { get }
    var libraryFiles: [LibraryFile] { get }
    var library: LibrarySlot { get }
}

public extension LibrarySetPlan {
    var changesAnything: Bool { library.isUnchanged == false }
    var action: ChangePlan.ScreenshotPlan.Action { LibraryPlanner.action(for: library) }
}

extension LibraryPusher.Target {
    init(_ plan: some LibrarySetPlan) {
        self.init(
            id: plan.id,
            label: plan.label,
            deviceClassID: plan.slotName,
            parent: plan.parent,
            files: plan.libraryFiles,
            slot: plan.library
        )
    }
}

extension Sequence where Element: LibrarySetPlan {
    /// A target for each slot that changes.
    var changingTargets: [LibraryPusher.Target] {
        filter(\.changesAnything).map(LibraryPusher.Target.init)
    }

    var imagesToAdd: Int {
        reduce(0) { total, item in
            guard case let .replace(_, adding) = item.action else { return total }
            return total + adding
        }
    }

    var imagesToRemove: Int {
        reduce(0) { total, item in
            guard case let .replace(removing, _) = item.action else { return total }
            return total + removing
        }
    }
}

public extension LibrarySlot {
    /// What a push does to the slot, in a few English words for a terminal.
    var summary: String {
        if toRemove.isEmpty, placementsToAdd == 0 {
            return posterFrames.isEmpty ? "change the order" : "change the poster frame"
        }
        return "remove \(toRemove.count), add \(placementsToAdd)"
    }
}

public extension CreativePlan {
    /// What a push does to the art, in a few English words for a terminal.
    var summary: String {
        switch (file, usesHeader) {
        case (nil, _): "\(locale) \(role.rawValue): will be removed"
        case (_?, true): "\(locale) \(role.rawValue): show the header"
        case let (file?, false): "\(locale) \(role.rawValue): put up \(file.fileName)"
        }
    }
}
