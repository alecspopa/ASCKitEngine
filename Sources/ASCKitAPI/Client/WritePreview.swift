import Foundation

/// One way of writing a body out, so two previews cannot format the same
/// request differently.
enum WritePreviewJSON {
    static func text(for value: some Encodable) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        guard let data = try? encoder.encode(value),
              let text = String(data: data, encoding: .utf8)
        else { return "(could not be written out)" }
        return text
    }
}
