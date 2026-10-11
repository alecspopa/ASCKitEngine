import CryptoKit
import Foundation

/// MD5 of a whole file, lowercase hex.
///
/// MD5 is a poor hash and a fine fingerprint. App Store Connect asks for it
/// when committing an upload, and reports it back as `sourceFileChecksum`,
/// which makes it the one way to tell an image it already holds from a new one.
public enum FileChecksum {
    public static func md5(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }

        var hasher = Insecure.MD5()
        // A screenshot is a few megabytes, and there may be a hundred of them.
        // Read in chunks rather than holding them all in memory.
        while let chunk = try handle.read(upToCount: 1 << 20), chunk.isEmpty == false {
            hasher.update(data: chunk)
        }
        return hasher.finalize().hexString
    }

    public static func md5(of data: Data) -> String {
        Insecure.MD5.hash(data: data).hexString
    }
}

/// The MD5 of each file, read once however often it is asked for.
///
/// One file can be the twin of several others, and reading it again for each
/// comparison would make a check cost as much as a copy.
struct ChecksumCache {
    private var known: [URL: String] = [:]

    /// Nil for a file that cannot be read. The caller decides what that means.
    mutating func md5(of url: URL) -> String? {
        if let checksum = known[url] { return checksum }
        let checksum = try? FileChecksum.md5(of: url)
        known[url] = checksum
        return checksum
    }
}

extension Sequence<UInt8> {
    /// Lowercase hex, two digits for each byte.
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
