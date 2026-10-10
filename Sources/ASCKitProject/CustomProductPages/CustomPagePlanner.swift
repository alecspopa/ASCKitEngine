import ASCKitAPI
import Foundation

/// Works out what a push of the custom product pages would change.
///
/// Only a page whose version takes changes gets a plan. The screenshots follow
/// `LibraryPlanner.screenshotSet`, the rule of every place.
public enum CustomPagePlanner {
    public static func plan(
        local: CustomPageContent,
        config: ProjectConfig,
        remote: RemoteCustomPages,
        record: AssetRecord = AssetRecord()
    ) -> CustomPagePlan {
        var texts: [CustomPagePlan.TextChange] = []
        var deepLinks: [CustomPagePlan.DeepLinkChange] = []
        var sets: [CustomPagePlan.SetPlan] = []
        var previewSets: [CustomPagePlan.PreviewSetPlan] = []
        var creativeSets: [CustomPagePlan.CreativeSetPlan] = []
        var placed: Set<CustomPageSlot> = []
        let names = CustomPageFolders.folderNames(for: remote)

        for page in remote.pages where page.isEditable {
            guard let version = page.version else { continue }
            let folder = names[page.id] ?? page.name
            let deviceClasses = config.screenshotDeviceClasses(for: .customPage(folder))

            if let change = deepLinkChange(page: page, version: version, settings: local.settings[folder]) {
                deepLinks.append(change)
            }

            for localization in version.localizations {
                let place = Place(page: page, folder: folder, localization: localization)
                if let text = local.text(page: folder, locale: localization.locale),
                   let change = textChange(text, at: place) {
                    texts.append(change)
                }
                creativeSets += creativePlans(at: place, local: local, record: record)
                previewSets += previewPlans(at: place, local: local, deviceClasses: deviceClasses, record: record)

                for deviceClass in deviceClasses {
                    let slot = CustomPageSlot(page: folder, locale: localization.locale, deviceClassID: deviceClass.id)
                    let files = local.screenshots(in: slot)
                    if files.isEmpty == false { placed.insert(slot) }
                    guard let library = LibraryPlanner.screenshotSet(
                        files: files, placements: localization.placements, locale: localization.locale,
                        deviceClass: deviceClass, emptied: local.emptied.contains(slot), record: record
                    ) else { continue }

                    sets.append(.init(
                        pageID: page.id,
                        pageName: page.name,
                        locale: localization.locale,
                        localizationID: localization.id,
                        deviceClass: deviceClass,
                        localFiles: files,
                        library: library
                    ))
                }
            }
        }

        return CustomPagePlan(
            textChanges: texts,
            deepLinkChanges: deepLinks,
            sets: sets,
            previewSets: previewSets,
            creativeSets: creativeSets,
            unplaced: unplaced(local: local, placed: placed, remote: remote, names: names)
        )
    }

    /// One language of one page, with the folder it is in.
    private struct Place {
        let page: RemoteCustomPage
        let folder: String
        let localization: RemoteCustomPageLocalization

        var label: String { "\(page.name) / \(localization.locale)" }
    }

    private static func deepLinkChange(
        page: RemoteCustomPage,
        version: RemoteCustomPageVersion,
        settings: CustomPageSettings?
    ) -> CustomPagePlan.DeepLinkChange? {
        guard let wanted = settings?.deepLink?.trimmingCharacters(in: .whitespacesAndNewlines),
              wanted.isEmpty == false,
              wanted != version.deepLink
        else {
            return nil
        }
        return .init(pageID: page.id, pageName: page.name, versionID: version.id, deepLink: wanted)
    }

    private static func textChange(_ text: CustomPageText, at place: Place) -> CustomPagePlan.TextChange? {
        let remote = place.localization

        // An empty box means "nothing here", which App Store Connect would
        // read as blanking the field. It is left alone instead.
        var promotionalText: String?
        if let wanted = text.promotionalText, wanted.isEmpty == false, wanted != (remote.promotionalText ?? "") {
            promotionalText = wanted
        }

        var toLink: [String] = []
        var toUnlink: [String] = []
        if let wanted = text.keywords {
            let linked = Set(remote.keywordIDs)
            let wantedSet = Set(wanted)
            var seen: Set<String> = []
            toLink = wanted.filter { linked.contains($0) == false && seen.insert($0).inserted }
            toUnlink = remote.keywordIDs.filter { wantedSet.contains($0) == false }
        }

        let change = CustomPagePlan.TextChange(
            pageID: place.page.id,
            pageName: place.page.name,
            locale: remote.locale,
            localizationID: remote.id,
            promotionalText: promotionalText,
            keywordsToLink: toLink,
            keywordsToUnlink: toUnlink
        )
        return change.changesAnything ? change : nil
    }

    /// Only a language with art of its own on disk, so a page that took its
    /// art from App Store Connect keeps it.
    private static func creativePlans(
        at place: Place,
        local: CustomPageContent,
        record: AssetRecord
    ) -> [CustomPagePlan.CreativeSetPlan] {
        let folder = local.creative[place.folder] ?? CreativeFolder()
        guard folder.files[place.localization.locale]?.isEmpty == false else { return [] }

        return CreativePlanner.plans(
            folder: folder, locales: [place.localization.locale], placements: place.localization.placements,
            record: record
        ).map {
            CustomPagePlan.CreativeSetPlan(
                pageID: place.page.id, label: place.label, localizationID: place.localization.id, plan: $0
            )
        }
    }

    private static func previewPlans(
        at place: Place,
        local: CustomPageContent,
        deviceClasses: [DeviceClass],
        record: AssetRecord
    ) -> [CustomPagePlan.PreviewSetPlan] {
        let localization = place.localization
        return deviceClasses.filter(\.takesPreviews).compactMap { deviceClass in
            let files = local.previews(in: CustomPageSlot(
                page: place.folder, locale: localization.locale, deviceClassID: deviceClass.id
            ))
            guard files.isEmpty == false else { return nil }

            let current = LibraryPlanner.current(
                in: localization.placements, locale: localization.locale,
                group: deviceClass.placementGroup, type: .appPreview
            )
            return CustomPagePlan.PreviewSetPlan(
                pageID: place.page.id,
                pageName: place.page.name,
                locale: localization.locale,
                localizationID: localization.id,
                deviceClass: deviceClass,
                localFiles: files,
                library: LibraryPlanner.slot(
                    files: files.map(\.libraryFile), current: current, record: record,
                    group: deviceClass.placementGroup, type: .appPreview
                )
            )
        }
    }

    /// Folders holding images that nothing will upload, and why.
    private static func unplaced(
        local: CustomPageContent,
        placed: Set<CustomPageSlot>,
        remote: RemoteCustomPages,
        names: [String: String]
    ) -> [CustomPagePlan.Unplaced] {
        var result: [CustomPagePlan.Unplaced] = []
        for (slot, files) in local.screenshots where files.isEmpty == false && placed.contains(slot) == false {
            let page = remote.pages.first { names[$0.id] == slot.page }
            let reason: CustomPagePlan.Unplaced.Reason = if let page {
                if page.isEditable == false {
                    .locked
                } else if page.version?.localization(slot.locale) == nil {
                    .noLanguage
                } else {
                    .deviceClassNotListed
                }
            } else {
                .noPage
            }
            result.append(.init(slot: slot, imageCount: files.count, reason: reason))
        }
        return result.sorted { $0.id < $1.id }
    }
}
