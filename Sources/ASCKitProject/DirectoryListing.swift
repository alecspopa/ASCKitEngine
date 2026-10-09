import Foundation

/// One way to list a folder, so every reader skips the same files.
enum DirectoryListing {
    /// Files that turn up in image folders but are not content. `.DS_Store` is
    /// not here because `.skipsHiddenFiles` already drops it.
    static let strayFileNames: Set<String> = ["Thumbs.db"]

    /// Empty when the folder is missing or cannot be read.
    static func entries(in directory: URL, keys: [URLResourceKey] = [.isDirectoryKey]) -> [URL] {
        (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        )) ?? []
    }

    /// `hasDirectoryPath` only looks for a trailing slash on the string, so it
    /// is not a reliable answer. Ask the file system.
    static func isDirectory(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) ?? false
    }

    static func directories(in directory: URL) -> [URL] {
        entries(in: directory)
            .filter(isDirectory)
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Everything that is not a directory and not a stray file. A file with the
    /// wrong extension is kept on purpose, so a check can report it.
    static func files(
        in directory: URL,
        keys: [URLResourceKey] = [.isDirectoryKey],
        ignoring extra: Set<String> = []
    ) -> [URL] {
        entries(in: directory, keys: keys)
            .filter { isDirectory($0) == false }
            .filter { strayFileNames.contains($0.lastPathComponent) == false && extra.contains($0.lastPathComponent) == false }
            .sortedNaturally()
    }
}
