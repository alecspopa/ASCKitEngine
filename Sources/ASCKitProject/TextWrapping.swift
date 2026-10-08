import Foundation

/// Breaking a sentence into lines, so a terminal does not decide where it
/// breaks.
///
/// Shared, so the plan and the command line wrap the same text the same way.
public enum TextWrapping {
    /// Splits on spaces at the last word that fits. A word longer than the
    /// width gets a line of its own rather than being cut.
    public static func lines(_ text: String, at width: Int = 76) -> [String] {
        var wrapped: [String] = []
        for paragraph in text.split(separator: "\n", omittingEmptySubsequences: false) {
            var line = ""
            for word in paragraph.split(separator: " ") {
                if line.isEmpty {
                    line = String(word)
                } else if line.count + 1 + word.count <= width {
                    line += " \(word)"
                } else {
                    wrapped.append(line)
                    line = String(word)
                }
            }
            wrapped.append(line)
        }
        return wrapped
    }
}
