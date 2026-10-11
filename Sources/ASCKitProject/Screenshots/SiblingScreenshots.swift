import ASCKitAPI
import Foundation

/// Finding the language next door that got the newer screenshots, and copying
/// them across.
///
/// `es-ES` and `es-MX` read the same pictures. A new export usually lands in
/// one of them, and the other keeps last month's. The check says the older one
/// has drifted from the source language, and it is right, but the answer is not
/// in the source language. It is in the language beside it.
///
/// Only inside one base language. The `en-US` screenshots are English pictures,
/// and copying them into `es-ES` would publish a Spanish listing with English
/// artwork. App Store Connect already does that by itself wherever a language
/// has no screenshots, and saying it on purpose is what the checkbox in
/// `usesSourceScreenshots` is for.
///
/// A copy is a decision about how the app is translated, so it is written into
/// `copiesScreenshotsFrom`. It is made again when pictures are filed into the
/// language it comes from, and when a version folder is made.
public enum SiblingScreenshots {
    /// One language that could take another language's screenshots.
    public struct Offer: Sendable, Hashable, Identifiable {
        /// The language that is behind.
        public let locale: String

        /// The language beside it holding the newer set.
        public let from: String

        public let deviceClassID: String

        /// How many files would land in `locale`.
        public let fileCount: Int

        /// When the newer set was last written.
        public let newest: Date

        /// When this language's set was last written. Nil when it has none.
        public let current: Date?

        public var id: String { "\(locale)|\(deviceClassID)|\(from)" }

        public init(
            locale: String,
            from: String,
            deviceClassID: String,
            fileCount: Int,
            newest: Date,
            current: Date?
        ) {
            self.locale = locale
            self.from = from
            self.deviceClassID = deviceClassID
            self.fileCount = fileCount
            self.newest = newest
            self.current = current
        }

        /// The device class as a person reads it, falling back to the id for a
        /// name ASCKit does not know.
        public var deviceName: String {
            DeviceClass.named(deviceClassID)?.displayName ?? deviceClassID
        }

        /// What the copy would do, in one line.
        public var summary: String { String(localized: summaryResource) }

        private var summaryResource: LocalizedStringResource {
            if current == nil {
                LocalizedStringResource("""
                \(locale) has no \(deviceName) screenshots. \
                \(from) has \(fileCount) screenshots, and reads the same words.
                """, bundle: .here)
            } else {
                LocalizedStringResource("""
                The \(from) \(deviceName) screenshots are newer than the \(locale) ones. \
                Copying brings \(fileCount) screenshots across.
                """, bundle: .here)
            }
        }
    }
}
