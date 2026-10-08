import ASCKitAPI
import Foundation

/// Where one field of one language stands against App Store Connect.
///
/// A field this version did not change has no status. It says the same as the
/// version on sale, and there is nothing to point out.
public enum TextStatus: Sendable, Hashable {
    /// The file says something App Store Connect does not hold yet.
    case notPushed

    /// App Store Connect holds what the file says, and it differs from the
    /// version on sale.
    case pushed
}

public extension RemoteListing {
    /// Where a field stands, given what its file says.
    ///
    /// Nil for a field the file leaves out, because a push leaves that field
    /// alone. Nil as well for a field that matches the store, when the words of
    /// the version on sale were not read.
    func textStatus(of field: MetadataField, locale: String, value: String?) -> TextStatus? {
        guard let value else { return nil }

        let store = field.isAppInfoField ? appInfoLocalizations : versionLocalizations
        guard Self.same(value, store[locale]?.values[field.rawValue]) else { return .notPushed }

        guard let live else { return nil }
        let released = field.isAppInfoField ? live.appInfoLocalizations : live.versionLocalizations
        return Self.same(value, released[locale]?.values[field.rawValue]) ? nil : .pushed
    }

    /// Apple returns an empty string for a field that was never set, so empty
    /// and missing are the same words.
    private static func same(_ value: String, _ held: String?) -> Bool {
        value == (held ?? "")
    }
}
