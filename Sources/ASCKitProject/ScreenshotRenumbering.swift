import Foundation

/// Puts screenshots in a new order by renumbering their file names.
///
/// The file name is what decides the order, so moving an image means renaming
/// it. The number is everything before the first hyphen. The rest of the name
/// stays exactly as it is, because it is the name App Store Connect holds.
public enum ScreenshotRenumbering {
    /// `01-shopping-iPhone-6.9-en_US.png` becomes `shopping-iPhone-6.9-en_US`.
    public static func nameWithoutNumber(of fileName: String) -> String {
        let base = (fileName as NSString).deletingPathExtension
        guard let hyphen = base.firstIndex(of: "-") else { return base }

        let prefix = String(base[base.startIndex ..< hyphen])
        guard prefix.allSatisfy(\.isNumber), prefix.isEmpty == false else { return base }
        return String(base[base.index(after: hyphen)...])
    }

    public static func fileName(
        position: Int,
        nameWithoutNumber: String,
        extension pathExtension: String
    ) -> String {
        let number = String(format: "%02d", position)
        let base = nameWithoutNumber.isEmpty ? number : "\(number)-\(nameWithoutNumber)"
        return pathExtension.isEmpty ? base : "\(base).\(pathExtension)"
    }

    /// What each file should be called once the list is in this order.
    ///
    /// Returns only the ones that actually move, so a reorder that changes
    /// nothing renames nothing.
    public static func plan(for orderedURLs: [URL]) -> [(from: URL, to: URL)] {
        orderedURLs.enumerated().compactMap { position, url in
            let wanted = fileName(
                position: position + 1,
                nameWithoutNumber: nameWithoutNumber(of: url.lastPathComponent),
                extension: url.pathExtension
            )
            guard wanted != url.lastPathComponent else { return nil }
            return (url, url.deletingLastPathComponent().appending(path: wanted))
        }
    }

    /// Renames the files into the given order, keeping the name each one
    /// already carries.
    public static func apply(orderedURLs: [URL]) throws {
        try apply(ordered: orderedURLs.map {
            (url: $0, name: nameWithoutNumber(of: $0.lastPathComponent))
        })
    }

    /// Renames the files into the given order, with the new name said out loud.
    ///
    /// A file arriving from outside the folder has no number to count from, and
    /// a file landing in another language needs the name that language gives
    /// it, so the caller supplies the name.
    ///
    /// Everything moves aside first. Renaming in place would have `02` land on
    /// a name `01` has not vacated yet, and the loser is overwritten.
    public static func apply(ordered: [(url: URL, name: String)]) throws {
        let moves = ordered.enumerated().compactMap { position, item -> (from: URL, to: URL)? in
            let wanted = fileName(
                position: position + 1,
                nameWithoutNumber: item.name,
                extension: item.url.pathExtension
            )
            guard wanted != item.url.lastPathComponent else { return nil }
            return (item.url, item.url.deletingLastPathComponent().appending(path: wanted))
        }
        guard moves.isEmpty == false else { return }

        let manager = FileManager.default
        var parked: [(temporary: URL, destination: URL)] = []

        for move in moves {
            let temporary = move.from
                .deletingLastPathComponent()
                .appending(path: ".asckit-moving-\(UUID().uuidString)")
            try manager.moveItem(at: move.from, to: temporary)
            parked.append((temporary, move.to))
        }

        for move in parked {
            if manager.fileExists(atPath: move.destination.path) {
                try manager.removeItem(at: move.destination)
            }
            try manager.moveItem(at: move.temporary, to: move.destination)
        }
    }
}
