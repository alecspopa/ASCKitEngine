import Foundation

extension Data {
    /// JWT uses base64url with the padding removed.
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacing("+", with: "-")
            .replacing("/", with: "_")
            .replacing("=", with: "")
    }

    init?(base64URLEncoded string: String) {
        var padded = string
            .replacing("-", with: "+")
            .replacing("_", with: "/")
        let remainder = padded.count % 4
        if remainder > 0 { padded += String(repeating: "=", count: 4 - remainder) }
        self.init(base64Encoded: padded)
    }
}
