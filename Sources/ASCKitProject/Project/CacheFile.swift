import Foundation

/// One JSON file in the project's cache folder.
///
/// A cache is what App Store Connect said last, kept so a check works with no
/// network. A file that is not there and a file that is damaged mean the
/// same thing to a reader: ask App Store Connect again.
struct CacheFile<Value: Codable>: Sendable {
    /// The path inside the cache folder.
    let path: String
    var pretty = true
    var datesAsISO8601 = false
    var atomic = false

    func url(in project: Project) -> URL {
        project.cacheURL.appending(path: path)
    }

    func load(in project: Project) -> Value? {
        ProjectJSON.read(Value.self, from: url(in: project), datesAsISO8601: datesAsISO8601)
    }

    /// Makes the cache folder with the `.gitignore` that empties it first. A
    /// project made before the folder existed has neither.
    func save(_ value: Value, in project: Project) throws {
        try ProjectScaffold.makeCache(at: project.cacheURL)
        try ProjectJSON.write(
            value, to: url(in: project), pretty: pretty, datesAsISO8601: datesAsISO8601, atomic: atomic
        )
    }
}
