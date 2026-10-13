import Foundation

/// The mark a remove leaves on a slot that somebody emptied on purpose: a
/// screenshot set, a preview set, or the header or search results art.
///
/// Only a marked slot takes App Store Connect's images off on a push. A slot
/// that is empty because a read wrote no files leaves them alone. The mark
/// lives in the slot's own folder, so it moves and goes with it. It is a
/// hidden file, so a listing of the folder never shows it.
public enum EmptiedMark {
    /// The mark of a screenshot set or a preview set.
    public static let name = ".asckit-emptied"

    /// The art of both roles shares one folder, so each role has its own mark.
    public static func name(_ role: CreativeRole) -> String {
        "\(name)-\(role.rawValue)"
    }

    public static func isSet(in directory: URL, name: String = name) -> Bool {
        FileManager.default.fileExists(atPath: directory.appending(path: name).path)
    }

    /// Setting the mark makes the folder when it is not there yet.
    public static func set(_ emptied: Bool, in directory: URL, name: String = name) throws {
        let marker = directory.appending(path: name)
        let exists = FileManager.default.fileExists(atPath: marker.path)
        if emptied, exists == false {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try Data().write(to: marker)
        } else if emptied == false, exists {
            try FileManager.default.removeItem(at: marker)
        }
    }
}
