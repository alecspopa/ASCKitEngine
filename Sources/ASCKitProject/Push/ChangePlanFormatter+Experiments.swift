import Foundation

/// Its own file, because `ChangePlanFormatter` is at the length limit.
public extension ChangePlanFormatter {
    /// The count for the test images, in the words the screenshots use.
    static func count(of plan: ExperimentPlan) -> String? {
        guard plan.hasChanges else { return nil }
        var pieces = imagePieces(
            sets: plan.changingSets.count + plan.changingPreviewSets.count,
            adding: plan.imagesToAdd,
            removing: plan.imagesToRemove
        )
        if plan.creativeSets.contains(where: \.plan.changesAnything) {
            pieces.append(String(localized: "header and search results art", bundle: .module))
        }
        return pieces.formatted(.list(type: .and))
    }

    /// The count for the custom product pages: the text first, then the
    /// images in the words the screenshots use.
    static func count(of plan: CustomPagePlan) -> String? {
        guard plan.hasChanges else { return nil }
        var pieces: [String] = []
        let texts = plan.changingTexts.count + plan.deepLinkChanges.count
        if texts > 0 {
            pieces.append(String(localized: "\(texts) text changes", bundle: .module))
        }
        pieces += imagePieces(
            sets: plan.changingSets.count + plan.changingPreviewSets.count,
            adding: plan.imagesToAdd,
            removing: plan.imagesToRemove
        )
        if plan.changingCreativeSets.isEmpty == false {
            pieces.append(String(localized: "header and search results art", bundle: .module))
        }
        return pieces.formatted(.list(type: .and))
    }

    private static func imagePieces(sets: Int, adding: Int, removing: Int) -> [String] {
        guard sets > 0 else { return [] }
        if adding > 0 {
            return [String(localized: "\(sets) sets, \(adding) images", bundle: .module)]
        } else if removing > 0 {
            return [String(localized: "\(sets) sets, removing \(removing) images", bundle: .module)]
        }
        return [String(localized: "\(sets) sets in a new order", bundle: .module)]
    }
}
