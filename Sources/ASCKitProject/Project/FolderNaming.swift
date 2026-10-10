import Foundation

/// Names from App Store Connect as folder names, for tests, treatments and
/// custom product pages.
public enum FolderNaming {
    /// A name from App Store Connect as a folder name.
    ///
    /// The name stays readable. Only what a file system refuses, or what would
    /// read as a path, is replaced.
    public static func folderName(for name: String) -> String {
        let cleaned = name
            .map { "/:\\".contains($0) || $0.isNewline ? "-" : $0 }
            .map(String.init)
            .joined()
            .trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: ".")))
        return cleaned.isEmpty ? "untitled" : cleaned
    }

    /// The folder name of each item, keyed by its id.
    ///
    /// Two items can share a name, and one folder must not hold both. The
    /// second in id order gets the end of its id, so the same two items are
    /// named the same way on every read. A name in `taken`, in any case, is
    /// already used.
    public static func folderNames(
        for items: [(id: String, name: String)],
        taken: Set<String> = []
    ) -> [String: String] {
        var result: [String: String] = [:]
        var taken = Set(taken.map { $0.lowercased() })
        for item in items.sorted(by: { $0.id < $1.id }) {
            var candidate = folderName(for: item.name)
            if taken.contains(candidate.lowercased()) {
                candidate += " (\(item.id.suffix(4)))"
            }
            taken.insert(candidate.lowercased())
            result[item.id] = candidate
        }
        return result
    }
}
