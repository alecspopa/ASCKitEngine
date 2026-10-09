import ASCKitAPI
import Foundation

/// The header and search results images in the inbox, named like
/// `header-en_US.png`. One file shows on every device, so the name says the
/// role and the language and no device class.
public extension Inbox {
    /// One waiting header or search results image, and the language it goes to.
    struct CreativeArrival: Sendable, Hashable, Identifiable {
        public let file: ScreenshotFile
        public let locale: String
        public let role: CreativeRole

        public var id: URL { file.url }

        public init(file: ScreenshotFile, locale: String, role: CreativeRole) {
            self.file = file
            self.locale = locale
            self.role = role
        }
    }

    // MARK: - Filing it

    /// Puts each image in as the art of its role, in place of the file there,
    /// and moves the inbox copy to the Trash.
    internal static func fileCreative(
        _ arrivals: [CreativeArrival], version: String, in project: Project, into outcome: inout Outcome
    ) throws {
        for arrival in arrivals {
            // Removed first rather than by `setCreative`, so the replaced file
            // is named in the outcome with the rest of the Trash.
            outcome.trashed += try LibraryContentWriter.removeCreative(
                role: arrival.role, locale: arrival.locale, at: .version(version), in: project
            )
            _ = try LibraryContentWriter.setCreative(
                from: arrival.file.url, role: arrival.role, locale: arrival.locale,
                at: .version(version), in: project
            )

            // Only once the copy is in the folder, as with a screenshot.
            var landed: NSURL?
            try FileManager.default.trashItem(at: arrival.file.url, resultingItemURL: &landed)
            if let landed = landed as URL? { outcome.trashed.append(landed) }
            outcome.creative.append(arrival)
        }
    }
}

// MARK: - Where it would go

extension Inbox.Plan {
    /// Adds one header or search results image, or the reason it is refused.
    ///
    /// The checks are the ones the project check runs on a filed image, so
    /// the inbox and the check refuse a file for the same stated reason.
    mutating func addCreative(
        _ file: ScreenshotFile,
        named name: Result<ScreenshotNaming.CreativeParts, ScreenshotNaming.Refusal>,
        config: ProjectConfig,
        refData: AssetLibraryRefData?
    ) {
        let parts: ScreenshotNaming.CreativeParts
        switch name {
        case let .success(read):
            parts = read
        case let .failure(refusal):
            refusals.append(Inbox.Refusal(file: file, reason: refusal.description, hasInvalidName: refusal.hasInvalidName))
            return
        }

        // One file shows in a role, so a second file for it has nowhere to go.
        if let first = creative.first(where: { $0.locale == parts.locale && $0.role == parts.role }) {
            let reason = Self.alreadyFilled(by: first.file.fileName, parts: parts)
            refusals.append(Inbox.Refusal(file: file, reason: String(localized: reason)))
            return
        }

        let problems = Validator(config: config, refData: refData).validateCreativeFile(
            CreativeFile(screenshot: file), role: parts.role, locale: parts.locale, path: file.fileName
        )
        .filter { $0.severity == .error }

        guard problems.isEmpty else {
            let alphaOnly = problems.allSatisfy { $0.kind == .creativeHasAlpha }
            let reason = problems
                .map { problem in
                    let message = String(localized: problem.message)
                    // A channel that can be cleared is said in one line, as
                    // for a screenshot, because the way to clear it is offered
                    // beside the refusal.
                    guard alphaOnly == false, let fix = problem.fix else { return message }
                    return "\(message) \(String(localized: fix))"
                }
                .joined(separator: " ")
            refusals.append(Inbox.Refusal(file: file, reason: reason, hasClearableAlpha: alphaOnly))
            return
        }

        creative.append(Inbox.CreativeArrival(file: file, locale: parts.locale, role: parts.role))
    }

    /// Whole sentences in `if` statements, so the string catalog sees both.
    private static func alreadyFilled(
        by first: String, parts: ScreenshotNaming.CreativeParts
    ) -> LocalizedStringResource {
        if parts.role == .header {
            return LocalizedStringResource(
                "\(first) is already the \(parts.locale) header. Keep one of the two files.", bundle: .here
            )
        }
        return LocalizedStringResource("""
        \(first) is already the \(parts.locale) search results image. Keep one of the two files.
        """, bundle: .here)
    }
}

extension CreativeFile {
    /// A waiting image, read as art.
    init(screenshot file: ScreenshotFile) {
        self.init(
            url: file.url, fileName: file.fileName, byteCount: file.byteCount, media: .image,
            pixelWidth: file.pixelWidth, pixelHeight: file.pixelHeight, hasAlpha: file.hasAlpha,
            duration: nil, frameRate: nil
        )
    }
}
