import ASCKitAPI
import Foundation

/// What a push of the custom product pages would do.
///
/// Kept apart from `ChangePlan` for the reason `ExperimentPlan` is: a page
/// belongs to no version of the app, and it is read and pushed without one.
public struct CustomPagePlan: Sendable {
    /// The words of one language of a page.
    public struct TextChange: Sendable, Identifiable {
        public let pageID: String
        public let pageName: String
        public let locale: String
        public let localizationID: String

        /// The new promotional text. Nil when it stays as it is.
        public let promotionalText: String?
        public let keywordsToLink: [String]
        public let keywordsToUnlink: [String]

        public var id: String { "\(localizationID)|text" }
        public var changesAnything: Bool {
            promotionalText != nil || keywordsToLink.isEmpty == false || keywordsToUnlink.isEmpty == false
        }

        public var label: String { "\(pageName) / \(locale)" }
    }

    /// The deep link of one page. It belongs to the version of the page, not
    /// to a language.
    public struct DeepLinkChange: Sendable, Identifiable {
        public let pageID: String
        public let pageName: String
        public let versionID: String
        public let deepLink: String

        public var id: String { "\(versionID)|deepLink" }
    }

    /// The screenshots of one device class in one language of a page.
    public struct SetPlan: Sendable, Identifiable {
        public let pageID: String
        public let pageName: String
        public let locale: String
        public let localizationID: String
        public let deviceClass: DeviceClass
        public let localFiles: [ScreenshotFile]

        /// How the slot compares in the App Asset Library.
        public let library: LibrarySlot

        public var id: String { "\(pageID)|\(locale)|\(deviceClass.id)" }
        public var action: ChangePlan.ScreenshotPlan.Action { LibraryPlanner.action(for: library) }
        public var changesAnything: Bool { library.isUnchanged == false }
        public var remoteCount: Int { library.current.count }
        public var label: String { "\(pageName) / \(locale)" }
    }

    /// The app previews of one device class in one language of a page.
    public struct PreviewSetPlan: Sendable, Identifiable {
        public let pageID: String
        public let pageName: String
        public let locale: String
        public let localizationID: String
        public let deviceClass: DeviceClass
        public let localFiles: [PreviewFile]
        public let library: LibrarySlot

        public var id: String { "\(pageID)|\(locale)|\(deviceClass.id)|previews" }
        public var changesAnything: Bool { library.isUnchanged == false }
        public var action: ChangePlan.ScreenshotPlan.Action { LibraryPlanner.action(for: library) }
        public var label: String { "\(pageName) / \(locale)" }
    }

    /// The header or search results art of one language of a page.
    public struct CreativeSetPlan: Sendable, Identifiable {
        public let pageID: String
        public let label: String
        public let localizationID: String
        public let plan: CreativePlan

        public var id: String { "\(localizationID)|\(plan.role.rawValue)" }
    }

    /// A folder of images with no place to go.
    public struct Unplaced: Sendable, Hashable, Identifiable {
        public enum Reason: Sendable, Hashable {
            /// No page has this name. It was removed, or never existed.
            case noPage
            /// The version of the page is in review or approved, and takes no
            /// changes until somebody starts a new version in App Store
            /// Connect.
            case locked
            /// The page has no language with this code on App Store Connect,
            /// and ASCKit never makes one.
            case noLanguage
            case deviceClassNotListed
        }

        public let slot: CustomPageSlot
        public let imageCount: Int
        public let reason: Reason
        public var id: String { slot.path }
    }

    public let textChanges: [TextChange]
    public let deepLinkChanges: [DeepLinkChange]
    public let sets: [SetPlan]
    public let previewSets: [PreviewSetPlan]
    public let creativeSets: [CreativeSetPlan]
    public let unplaced: [Unplaced]

    public init(
        textChanges: [TextChange] = [],
        deepLinkChanges: [DeepLinkChange] = [],
        sets: [SetPlan] = [],
        previewSets: [PreviewSetPlan] = [],
        creativeSets: [CreativeSetPlan] = [],
        unplaced: [Unplaced] = []
    ) {
        self.textChanges = textChanges
        self.deepLinkChanges = deepLinkChanges
        self.sets = sets
        self.previewSets = previewSets
        self.creativeSets = creativeSets
        self.unplaced = unplaced
    }

    public var changingTexts: [TextChange] { textChanges.filter(\.changesAnything) }
    public var changingSets: [SetPlan] { sets.filter(\.changesAnything) }
    public var changingPreviewSets: [PreviewSetPlan] { previewSets.filter(\.changesAnything) }
    public var changingCreativeSets: [CreativeSetPlan] { creativeSets.filter(\.plan.changesAnything) }

    public var hasTextChanges: Bool { changingTexts.isEmpty == false || deepLinkChanges.isEmpty == false }
    public var hasImageChanges: Bool {
        changingSets.isEmpty == false || changingPreviewSets.isEmpty == false || changingCreativeSets.isEmpty == false
    }

    public var hasChanges: Bool { hasTextChanges || hasImageChanges }

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

    /// Whether anything changes on one page.
    public func changes(pageID: String) -> Bool {
        changingTexts.contains { $0.pageID == pageID }
            || deepLinkChanges.contains { $0.pageID == pageID }
            || changingSets.contains { $0.pageID == pageID }
            || changingPreviewSets.contains { $0.pageID == pageID }
            || changingCreativeSets.contains { $0.pageID == pageID }
    }

    /// One line for each change on one page, for a terminal. English, because
    /// a terminal reads it.
    public func lines(pageID: String) -> [String] {
        let deepLinks = deepLinkChanges.filter { $0.pageID == pageID }.map { "deep link: \($0.deepLink)" }
        let texts = changingTexts.filter { $0.pageID == pageID }.flatMap { item in
            var lines: [String] = []
            if let text = item.promotionalText { lines.append("\(item.locale) promotional text: \(text)") }
            if item.keywordsToLink.isEmpty == false {
                lines.append("\(item.locale) link keywords: \(item.keywordsToLink.joined(separator: ", "))")
            }
            if item.keywordsToUnlink.isEmpty == false {
                lines.append("\(item.locale) unlink keywords: \(item.keywordsToUnlink.joined(separator: ", "))")
            }
            return lines
        }
        let screenshots = changingSets.filter { $0.pageID == pageID }.map { item in
            "\(item.locale)/\(item.deviceClass.id) screenshots: \(ExperimentPlan.describe(item.library))"
        }
        let previews = changingPreviewSets.filter { $0.pageID == pageID }.map { item in
            "\(item.locale)/\(item.deviceClass.id) previews: \(ExperimentPlan.describe(item.library))"
        }
        let art = changingCreativeSets.filter { $0.pageID == pageID }.map { item in
            let locale = item.plan.locale
            return switch (item.plan.file, item.plan.usesHeader) {
            case (nil, _): "\(locale) \(item.plan.role.rawValue): will be removed"
            case (_?, true): "\(locale) \(item.plan.role.rawValue): show the header"
            case let (file?, false): "\(locale) \(item.plan.role.rawValue): put up \(file.fileName)"
            }
        }
        return deepLinks + texts + screenshots + previews + art
    }
}
