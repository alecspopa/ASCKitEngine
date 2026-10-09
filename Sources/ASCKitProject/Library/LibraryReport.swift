import ASCKitAPI
import Foundation

/// What `asckit library` prints: the app's library, and what is placed on each
/// language next to the old screenshot sets.
///
/// The two side by side answer whether App Store Connect shows images sent
/// with the old endpoints as placements. English, because a terminal reads it.
public enum LibraryReport {
    public static func lines(
        library: RemoteAssetLibrary?,
        listing: RemoteListing,
        experiments: RemoteExperiments? = nil,
        customPages: RemoteCustomPages? = nil
    ) -> [String] {
        var lines: [String] = []
        lines += libraryLines(library)
        lines.append("")
        lines.append("Version \(listing.versionString), \(listing.versionState?.rawValue ?? "state unknown")")
        lines += localeLines(
            locales: listing.versionLocalizations.keys.sorted(),
            sets: listing.screenshotSets,
            placements: listing.placements,
            indent: "  "
        )

        for experiment in experiments?.experiments ?? [] {
            for treatment in experiment.treatments {
                lines.append("")
                lines.append("Test \(experiment.name), \(treatment.name)")
                for localization in treatment.localizations {
                    lines += localeLines(
                        locales: [localization.locale],
                        sets: nil,
                        placements: localization.placements,
                        indent: "  "
                    )
                }
            }
        }

        for page in customPages?.pages ?? [] {
            guard let version = page.version else { continue }
            lines.append("")
            lines.append("Custom product page \(page.name), \(version.state?.rawValue ?? "state unknown")")
            for localization in version.localizations {
                lines += localeLines(
                    locales: [localization.locale],
                    sets: nil,
                    placements: localization.placements,
                    indent: "  "
                )
            }
        }
        return lines
    }

    /// The placement groups App Store Connect knows, with the types each one
    /// takes and the most it holds on a version.
    public static func referenceLines(_ data: AssetLibraryRefData) -> [String] {
        var lines = ["Placement groups"]
        for group in data.placementProfileGroups.sorted(by: { $0.placementProfileGroupId < $1.placementProfileGroupId }) {
            let id = group.placementProfileGroupId
            let types = data.placementTypes
                .filter { $0.specMappings?.contains { $0.placementGroupId == id } == true }
                .map { entry in
                    let most = data.maximumCount(feature: "APP_STORE_VERSIONS", type: entry.placementTypeId, group: id)
                    return entry.placementTypeId.rawValue + (most.map { " (at most \($0))" } ?? "")
                }
            lines.append("  \(id): \(group.platform ?? "no platform"), \(group.displayClassId ?? "no display class")")
            lines.append("    \(types.isEmpty ? "no placement types" : types.joined(separator: ", "))")
        }
        return lines
    }

    // MARK: - Pieces

    static func libraryLines(_ library: RemoteAssetLibrary?) -> [String] {
        guard let library else { return ["This app has no asset library on App Store Connect."] }

        let images = library.assets.filter { $0.media == .image }.count
        let videos = library.assets.filter { $0.media == .video }.count
        var lines = ["Asset library \(library.id). Images: \(images). Videos: \(videos)."]
        for asset in library.assets.sorted(by: { ($0.fileName ?? "") < ($1.fileName ?? "") }) {
            let placed = library.placementIDs[asset.id]?.count ?? 0
            let name = asset.referenceName.map { " \"\($0)\"" } ?? ""
            lines.append("  \(asset.fileName ?? asset.id)\(name): \(asset.media.rawValue.lowercased()), "
                + "\(asset.state?.rawValue ?? "state unknown"). Placements: \(placed).")
        }
        return lines
    }

    static func localeLines(
        locales: [String],
        sets: [RemoteScreenshotSet]?,
        placements: [RemotePlacement],
        indent: String
    ) -> [String] {
        var lines: [String] = []
        for locale in locales {
            lines.append("\(indent)\(locale)")
            // A treatment's old sets are not read: nothing pairs them.
            if let sets {
                let localSets = sets.filter { $0.locale == locale }
                let oldImages = localSets.reduce(0) { $0 + $1.screenshots.count }
                lines.append("\(indent)  Old screenshot sets: \(localSets.count). Images in them: \(oldImages).")
            }

            let here = placements.filter { $0.locale == locale }
            guard here.isEmpty == false else {
                lines.append("\(indent)  Placements: none.")
                continue
            }
            for slot in slots(of: here) {
                let names = slot.placements.map { $0.asset?.fileName ?? $0.asset?.id ?? "?" }
                lines.append("\(indent)  \(slot.type) \(slot.group): \(names.joined(separator: ", "))")
            }
        }
        return lines
    }

    public struct Slot {
        public let type: String
        public let group: String
        public var placements: [RemotePlacement]
    }

    /// Placements by type and group, each keeping the store's order.
    public static func slots(of placements: [RemotePlacement]) -> [Slot] {
        var order: [String] = []
        var grouped: [String: Slot] = [:]
        for placement in placements {
            let type = placement.type?.rawValue ?? "unknown type"
            let group = placement.group ?? "unknown group"
            let key = type + "|" + group
            if grouped[key] == nil {
                order.append(key)
                grouped[key] = Slot(type: type, group: group, placements: [])
            }
            grouped[key]?.placements.append(placement)
        }
        return order.compactMap { grouped[$0] }
    }
}
