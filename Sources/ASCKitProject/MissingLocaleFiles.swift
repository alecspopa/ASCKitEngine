import Foundation

/// The app information file a listed language has none of.
///
/// The locale list says which languages a project ships, and every name in it
/// needs a file of its own. A name with no file is nothing for a person to
/// decide about: the file it wants is an empty draft, and ASCKit knows how to
/// write one.
///
/// So the app writes them as it reads the folder, and nobody is asked to make a
/// file by hand. The validator still warns about the cases nothing here can
/// write, such as a folder the app has no permission for.
public enum MissingLocaleFiles {
    /// Writes an empty draft for every listed language whose file is missing,
    /// and says which languages got one.
    ///
    /// The newest version folder, which is the one the checker reads. A version
    /// nobody has started gets nothing, because a file written here would be
    /// the first thing in it. That covers a project with no version folder at
    /// all, and a version folder holding no app information file: `createVersion`
    /// makes that one empty on purpose.
    ///
    /// A draft rather than approved, the same as the file a new project is
    /// scaffolded with. Nothing has been written in this language yet, and an
    /// empty listing must not be publishable.
    ///
    /// Writes over nothing and reports no failure. A file already on disk is
    /// somebody's work, and a file that could not be written leaves the
    /// validator's warning standing, which says the same thing in words a
    /// person can act on.
    @discardableResult
    public static func write(in project: Project) -> [String] {
        guard
            let versions = try? project.versionNames(),
            let version = versions.last,
            hasStarted(version: version, in: project)
        else {
            return []
        }

        var written: [String] = []
        for locale in project.config.writtenLocales.sorted() {
            let url = project.informationURL(version: version, locale: locale)
            guard FileManager.default.fileExists(atPath: url.path) == false else { continue }

            do {
                try ContentWriter.writeAppInformation(
                    AppInformation(locale: locale, status: .draft),
                    version: version,
                    in: project
                )
                written.append(locale)
            } catch {
                continue
            }
        }
        return written
    }

    /// Whether somebody has written any of this version's listing text yet.
    ///
    /// One file is enough. Filling the gaps around it is the work this does,
    /// and a version with no file at all has no gaps, only a first file that
    /// has to be somebody's decision.
    private static func hasStarted(version: String, in project: Project) -> Bool {
        let folder = project.informationURL(version: version)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []
        return names.contains { $0.lowercased().hasSuffix(".json") }
    }
}
