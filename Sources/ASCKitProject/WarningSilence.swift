import ASCKitAPI
import Foundation

/// A warning somebody read and decided not to see again.
///
/// Everything but the severity, because a rule that turns a warning into an
/// error has changed its mind about how bad it is, and that is worth reading
/// again rather than hiding.
public struct SilencedWarning: Codable, Sendable, Hashable, Identifiable {
    public var area: Problem.Area

    /// The rule, not the words it wrote.
    ///
    /// The words are translated, so a silence kept by them would come back the
    /// day somebody read the app in another language. The rule is the same in
    /// every language, and it holds while the wording is edited.
    public var kind: Problem.Kind

    /// What the warning said, in English, so the file reads on its own and so
    /// a silence somebody fixed can still be named on screen.
    ///
    /// A note, not the identity. Nothing matches on it.
    public var message: String

    public var locale: String?
    public var deviceClass: String?
    public var field: MetadataField?

    /// Optional, so a file written before in-app purchases existed still reads.
    public var productID: String?
    public var territory: String?
    public var productField: ProductField?

    /// Optional, so a file written before subscription groups had words still
    /// reads.
    public var subscriptionGroup: String?
    public var groupField: GroupField?

    public var path: String?

    public var id: String {
        var parts = [
            area.rawValue, kind.rawValue, locale ?? "",
            deviceClass ?? "", field?.rawValue ?? "",
            productID ?? "", territory ?? "", productField?.rawValue ?? "",
            path ?? ""
        ]
        if let subscriptionGroup {
            parts += [subscriptionGroup, groupField?.rawValue ?? ""]
        }
        return parts.joined(separator: "|")
    }

    public init(silencing problem: Problem) {
        area = problem.area
        kind = problem.kind
        message = problem.message.english
        locale = problem.locale
        deviceClass = problem.deviceClassID
        field = problem.field
        productID = problem.productID
        territory = problem.territory
        productField = problem.productField
        subscriptionGroup = problem.subscriptionGroup
        groupField = problem.groupField
        path = problem.path
    }

    /// Whether this warning belongs to the products file rather than to a
    /// version.
    ///
    /// A product is not tied to a version, so a silence about one cannot live
    /// in a version folder. It would come back the day the next version folder
    /// is made.
    public var belongsToProducts: Bool {
        area == .products || area == .pricing
    }

    /// Whether this is the warning that was silenced.
    ///
    /// The rule and everything the rule is about: the same rule against a
    /// different language, field or file is a different warning and shows.
    public func matches(_ problem: Problem) -> Bool {
        problem.severity == .warning
            && problem.area == area
            && problem.kind == kind
            && problem.locale == locale
            && problem.deviceClassID == deviceClass
            && problem.field == field
            && problem.productID == productID
            && problem.territory == territory
            && problem.productField == productField
            && problem.subscriptionGroup == subscriptionGroup
            && problem.groupField == groupField
            && problem.path == path
    }
}

/// The warnings silenced in a check, and the files that hold them.
///
/// A check of a version reads the file beside the version and the file in the
/// products folder. `Location` says which silence goes where, and why.
///
/// The command line tool and the app both read and write through here, so a
/// warning silenced in one is silenced in the other.
public enum WarningSilence {
    public static let fileName = "silenced.json"

    /// Which file a silence goes in.
    ///
    /// A silence goes with the thing it is about. A listing warning belongs to
    /// one version, and goes away with the version folder. A product warning
    /// belongs to no version at all, so it sits with the products, and delete
    /// that folder and its silences go with it. Put in a version folder it
    /// would come back the day the next version folder was made.
    public enum Location: Sendable, Hashable {
        case version(String)
        case products

        /// The files a check of this version reads, in the order a list shows
        /// them.
        static func all(version: String) -> [Location] {
            [.version(version), .products]
        }

        public func url(in project: Project) -> URL {
            switch self {
            case let .version(version): project.versionURL(version).appending(path: fileName)
            case .products: project.productsURL.appending(path: fileName)
            }
        }

        /// The file from the project folder, the way a person types it.
        func path(in project: Project) -> String {
            switch self {
            case let .version(version): "\(project.config.versionsPath)/\(version)/\(fileName)"
            case .products: "\(project.config.productsPath)/\(fileName)"
            }
        }

        /// The one this warning belongs in.
        public static func of(_ warning: SilencedWarning, version: String) -> Location {
            warning.belongsToProducts ? .products : .version(version)
        }
    }

    /// One file, and the silences a call read from it, put in it or took out
    /// of it.
    public struct File: Sendable, Hashable {
        public let location: Location
        public let warnings: [SilencedWarning]
    }

    public static func url(version: String, in project: Project) -> URL {
        Location.version(version).url(in: project)
    }

    public static func productsURL(in project: Project) -> URL {
        Location.products.url(in: project)
    }

    /// What the file holds. The wrapper is there so the file can grow another
    /// key later without every reader of it changing.
    private struct Stored: Codable {
        var warnings: [SilencedWarning]
    }

    // MARK: - Reading

    /// The warnings silenced in this version.
    ///
    /// When the file is missing or cannot be read, this writes an empty one.
    /// Every warning then shows. A file from an older format cannot be read.
    public static func read(version: String, in project: Project) -> [SilencedWarning] {
        read(.version(version), in: project)
    }

    /// The warnings silenced about in-app purchases. This writes a missing or
    /// broken file again, the same as the version file.
    public static func readProducts(in project: Project) -> [SilencedWarning] {
        read(.products, in: project)
    }

    public static func read(_ location: Location, in project: Project) -> [SilencedWarning] {
        let url = location.url(in: project)
        if let data = try? Data(contentsOf: url),
           let stored = try? JSONDecoder().decode(Stored.self, from: data) {
            return stored.warnings
        }

        // A folder that a read made would show as a version, or as products
        // in a project that sells none.
        if FileManager.default.fileExists(atPath: url.deletingLastPathComponent().path) {
            try? write([], to: location, in: project)
        }
        return []
    }

    /// Everything silenced anywhere, for a check that covers a version and the
    /// products at the same time.
    ///
    /// In the order `asckit silence` numbers them. `--show` takes its number
    /// from this list.
    public static func readAll(version: String, in project: Project) -> [SilencedWarning] {
        readByFile(version: version, in: project).flatMap(\.warnings)
    }

    /// What `readAll` reads, one file at a time. The version's file comes
    /// first. It sorts each file in the order `write` uses, and it leaves out a
    /// file with no silence in it.
    public static func readByFile(version: String, in project: Project) -> [File] {
        Location.all(version: version).compactMap { location in
            let warnings = read(location, in: project).sorted()
            return warnings.isEmpty ? nil : File(location: location, warnings: warnings)
        }
    }

    /// Splits problems into the ones to show and the ones somebody has already
    /// dealt with.
    public static func split(
        _ problems: [Problem],
        by silenced: [SilencedWarning]
    ) -> (shown: [Problem], hidden: [Problem]) {
        var shown: [Problem] = []
        var hidden: [Problem] = []

        for problem in problems {
            if silenced.contains(where: { $0.matches(problem) }) {
                hidden.append(problem)
            } else {
                shown.append(problem)
            }
        }
        return (shown, hidden)
    }

    /// The silenced warnings this version no longer has.
    ///
    /// A file somebody fixed leaves its silence behind. A read keeps every
    /// silence that it can decode. A person can see the stale ones and clear
    /// them out.
    public static func stale(_ silenced: [SilencedWarning], against problems: [Problem]) -> [SilencedWarning] {
        silenced.filter { warning in problems.contains(where: warning.matches) == false }
    }

    // MARK: - Writing

    /// Silences these problems, and says how many were not silenced already.
    ///
    /// Warnings only. An error blocks publishing, and a way to hide one would
    /// be a way to publish a listing App Store Connect refuses.
    /// A warning about a product goes in the products file and a warning about
    /// the listing goes in the version's, so one call can be handed both.
    @discardableResult
    public static func silence(
        _ problems: [Problem],
        version: String,
        in project: Project
    ) throws -> Int {
        try silenceByFile(problems, version: version, in: project).reduce(0) { $0 + $1.warnings.count }
    }

    /// What `silence` does, with the new silences in each file. It leaves out
    /// a file that took no new silence.
    public static func silenceByFile(
        _ problems: [Problem],
        version: String,
        in project: Project
    ) throws -> [File] {
        let warnings = problems.warnings.map(SilencedWarning.init(silencing:))
        var files: [File] = []

        for location in Location.all(version: version) {
            let belonging = warnings.filter { Location.of($0, version: version) == location }
            guard belonging.isEmpty == false else { continue }

            var silenced = read(location, in: project)
            var added: [SilencedWarning] = []
            for warning in belonging {
                guard silenced.contains(warning) == false else { continue }
                silenced.append(warning)
                added.append(warning)
            }

            guard added.isEmpty == false else { continue }
            try write(silenced, to: location, in: project)
            files.append(File(location: location, warnings: added))
        }
        return files
    }

    /// Brings these warnings back. Anything already gone is left alone.
    @discardableResult
    public static func show(
        _ warnings: [SilencedWarning],
        version: String,
        in project: Project
    ) throws -> Int {
        var removed = 0
        for location in Set(warnings.map { Location.of($0, version: version) }) {
            let silenced = read(location, in: project)
            let kept = silenced.filter { warnings.contains($0) == false }

            guard kept.count != silenced.count else { continue }
            try write(kept, to: location, in: project)
            removed += silenced.count - kept.count
        }
        return removed
    }

    /// Brings every warning back, in this version and in the products, and
    /// leaves both files empty.
    @discardableResult
    public static func showAll(version: String, in project: Project) throws -> Int {
        try showAllByFile(version: version, in: project).reduce(0) { $0 + $1.warnings.count }
    }

    /// What `showAll` does, with the silences each file gave back. It leaves
    /// out a file that held none.
    public static func showAllByFile(version: String, in project: Project) throws -> [File] {
        let files = readByFile(version: version, in: project)
        for file in files {
            try write([], to: file.location, in: project)
        }
        return files
    }

    /// Writes the file, with an empty list too, because a read would write a
    /// missing file again.
    ///
    /// Sorted, so that silencing one warning today and another tomorrow moves
    /// one line in git rather than rewriting the file.
    private static func write(
        _ warnings: [SilencedWarning],
        to location: Location,
        in project: Project
    ) throws {
        let url = location.url(in: project)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]

        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try encoder.encode(Stored(warnings: warnings.sorted())).write(to: url)
    }
}

// MARK: - Words

/// What `asckit silence` says after it changes a file.
///
/// Each sentence holds a count, so it needs a plural rule from the catalog of
/// this package. The command prints the English.
public extension WarningSilence.File {
    /// After `silenceByFile` put these warnings in this file.
    func silencedSentence(in project: Project) -> LocalizedStringResource {
        let path = location.path(in: project)
        return switch location {
        case let .version(version):
            LocalizedStringResource(
                "Silenced \(warnings.count) warnings in \(version). They are in \(path).", bundle: .here
            )
        case .products:
            LocalizedStringResource(
                "Silenced \(warnings.count) warnings in every version. They are in \(path).", bundle: .here
            )
        }
    }

    /// After `showAllByFile` took these warnings out of this file.
    var shownSentence: LocalizedStringResource {
        switch location {
        case let .version(version):
            LocalizedStringResource("\(warnings.count) warnings show again in \(version).", bundle: .here)
        case .products:
            LocalizedStringResource("\(warnings.count) warnings show again in every version.", bundle: .here)
        }
    }
}

extension SilencedWarning: Comparable {
    /// The order they are written in, which is the order a person reads them:
    /// by what they are about, then by language.
    public static func < (lhs: SilencedWarning, rhs: SilencedWarning) -> Bool {
        if lhs.area != rhs.area {
            let order = Problem.Area.allCases
            return order.firstIndex(of: lhs.area)! < order.firstIndex(of: rhs.area)!
        }
        if lhs.locale != rhs.locale { return (lhs.locale ?? "") < (rhs.locale ?? "") }
        if lhs.kind != rhs.kind { return lhs.kind.rawValue < rhs.kind.rawValue }
        return lhs.id < rhs.id
    }
}
