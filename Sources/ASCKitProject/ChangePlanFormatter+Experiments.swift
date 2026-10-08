import Foundation

/// Its own file, because `ChangePlanFormatter` is at the length limit.
public extension ChangePlanFormatter {
    /// The count for the test images, in the words the screenshots use.
    static func count(of plan: ExperimentPlan) -> String? {
        guard plan.hasChanges else { return nil }
        var pieces: [String] = []
        let sets = plan.changingSets.count + plan.changingPreviewSets.count
        if sets > 0 {
            if plan.imagesToAdd > 0 {
                pieces.append(String(localized: "\(sets) sets, \(plan.imagesToAdd) images", bundle: .module))
            } else if plan.imagesToRemove > 0 {
                pieces.append(String(
                    localized: "\(sets) sets, removing \(plan.imagesToRemove) images", bundle: .module
                ))
            } else {
                pieces.append(String(localized: "\(sets) sets in a new order", bundle: .module))
            }
        }
        if plan.creativeSets.contains(where: \.plan.changesAnything) {
            pieces.append(String(localized: "header and search results art", bundle: .module))
        }
        return pieces.formatted(.list(type: .and))
    }
}
