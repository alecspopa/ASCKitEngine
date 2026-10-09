import Foundation

/// A `.p8` that has been read but not kept yet.
public struct PickedKey: Sendable, Equatable {
    public let fileName: String

    /// The key identifier the file name carries. A file renamed to anything
    /// else carries none, and then only a typed identifier says which key
    /// this is.
    public let keyID: String?

    public let pem: String

    public init(fileName: String, keyID: String?, pem: String) {
        self.fileName = fileName
        self.keyID = keyID
        self.pem = pem
    }
}
