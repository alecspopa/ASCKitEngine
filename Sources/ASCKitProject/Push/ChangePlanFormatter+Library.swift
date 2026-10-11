import Foundation

extension ChangePlanFormatter {
    static func previewLines(_ plan: ChangePlan) -> [String] {
        let changing = plan.previewPlans.filter(\.changesAnything)
        guard changing.isEmpty == false else { return [] }

        var lines = [String(localized: Words.previews)]
        for item in changing {
            let words = describeOrderOnly(item.library) ?? describeVideos(item.action)
            lines.append("  \(item.locale), \(item.deviceClass.displayName): \(words)")
        }
        return lines + [""]
    }

    static func creativeLines(_ plan: ChangePlan) -> [String] {
        let changing = plan.creativePlans.filter(\.changesAnything)
        guard changing.isEmpty == false else { return [] }

        var lines = [String(localized: Words.creative)]
        for item in changing {
            let role = item.role == .header
                ? String(localized: "header", bundle: .module)
                : String(localized: "search results", bundle: .module)
            let words = if let file = item.file, item.usesHeader {
                String(localized: "show the header, \(file.fileName)", bundle: .module)
            } else if let file = item.file {
                String(localized: "put up \(file.fileName)", bundle: .module)
            } else {
                String(localized: "will be removed", bundle: .module)
            }
            lines.append("  \(item.locale), \(role): \(words)")
        }
        return lines + [""]
    }

    private static let unusedHeading = LocalizedStringResource(
        "Not used, because the language shows the source language's. A push moves them to the Trash:",
        bundle: .here
    )

    static func unusedCount(_ plan: ChangePlan) -> String? {
        guard plan.unusedFiles.isEmpty == false else { return nil }
        return String(localized: "\(plan.unusedFiles.count) unused files", bundle: .module)
    }

    static func unusedLines(_ plan: ChangePlan) -> [String] {
        guard plan.unusedFiles.isEmpty == false else { return [] }

        var lines = [String(localized: unusedHeading)]
        for file in plan.unusedFiles {
            let slot = switch file.slot {
            case let .screenshots(deviceClass): deviceClass.displayName
            case let .previews(deviceClass):
                String(localized: "\(deviceClass.displayName) app preview", bundle: .module)
            case .creative(.header): String(localized: "header", bundle: .module)
            case .creative(.searchResults): String(localized: "search results", bundle: .module)
            }
            lines.append("  \(file.locale), \(slot): \(file.fileName)")
        }
        return lines + [""]
    }

    /// A slot of the library that keeps every file it has, and changes only
    /// their order or a poster frame. Nil when a file comes or goes.
    static func describeOrderOnly(_ slot: LibrarySlot) -> String? {
        guard slot.toRemove.isEmpty, slot.placementsToAdd == 0 else { return nil }
        return slot.posterFrames.isEmpty
            ? String(localized: "change the order", bundle: .module)
            : String(localized: "change the poster frame", bundle: .module)
    }

    private static func describeVideos(_ action: ChangePlan.ScreenshotPlan.Action) -> String {
        switch action {
        case .unchanged:
            String(localized: Words.noChange)
        case let .replace(removing, adding) where removing == 0:
            String(localized: "add \(adding) videos", bundle: .module)
        case let .replace(removing, 0):
            String(localized: "remove all \(removing) videos", bundle: .module)
        case let .replace(removing, adding):
            String(localized: "remove \(removing) videos, then add \(adding) videos", bundle: .module)
        }
    }
}
