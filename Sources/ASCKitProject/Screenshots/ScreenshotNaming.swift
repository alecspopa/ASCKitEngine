import Foundation

/// What the name of a screenshot waiting to be filed says about it.
///
///     03-shopping-iPhone-6.9-en_US.png
///     |  |        |          |
///     |  |        |          the language, `en_US` or `en`
///     |  |        the device class, as `asckit.json` names it
///     |  what the screenshot shows
///     where it goes in the set
///
/// The name is the whole instruction, so nothing has to be asked and a folder
/// of images can be dropped in one go. The app and the command line tool both
/// read a waiting file through here. A name that files one way in the window
/// cannot file another way in the terminal.
public enum ScreenshotNaming {
    /// What every waiting file is called. Said out loud in each refusal,
    /// because a person reading one is about to rename a file.
    public static let example = "03-shopping-iPhone-6.9-en_US.png"

    /// What one file name says.
    public struct Parts: Sendable, Hashable {
        /// The language, as App Store Connect writes it.
        public let locale: String

        public let deviceClass: DeviceClass

        /// What the screenshot shows. The part that reads the same in every
        /// language, and the part two languages are matched on.
        public let imageName: String

        public init(locale: String, deviceClass: DeviceClass, imageName: String) {
            self.locale = locale
            self.deviceClass = deviceClass
            self.imageName = imageName
        }
    }

    /// Why a name cannot say where its image goes.
    ///
    /// The words live here rather than in either front end, so the window and
    /// the terminal refuse the same file for the same stated reason.
    public enum Refusal: Error, Sendable, Hashable, CustomLocalizedStringResourceConvertible {
        case noLanguage(fileName: String, token: String)
        case languageNotShipped(fileName: String, locale: String, shipped: [String])
        case twoLanguagesFit(fileName: String, language: String, candidates: [String])
        case noDevice(fileName: String, listed: [String])
        case deviceNotListed(fileName: String, device: DeviceClass, listed: [String])
        case noName(fileName: String)

        public var localizedStringResource: LocalizedStringResource {
            switch self {
            case let .noLanguage(fileName, token):
                LocalizedStringResource("""
                \(fileName) ends with \"\(token)\", which is not a language. \
                Name it like \(example).
                """, bundle: .here)

            case let .languageNotShipped(fileName, locale, shipped):
                if shipped.isEmpty {
                    LocalizedStringResource("""
                    \(fileName) is for \(locale). This project ships no languages yet.
                    """, bundle: .here)
                } else {
                    LocalizedStringResource("""
                    \(fileName) is for \(locale), which this project does not ship. \
                    It ships \(list(shipped)).
                    """, bundle: .here)
                }

            case let .twoLanguagesFit(fileName, language, candidates):
                LocalizedStringResource("""
                \(fileName) says \(language), and this project ships \(list(candidates)). \
                Say which one, such as \(underscored(candidates.first)).
                """, bundle: .here)

            case let .noDevice(fileName, listed):
                LocalizedStringResource("""
                \(fileName) does not say which device it is for. Name it like \(example). \
                This project lists \(list(listed)).
                """, bundle: .here)

            case let .deviceNotListed(fileName, device, listed):
                LocalizedStringResource("""
                \(fileName) is for \(device.displayName), which this project does not list. \
                It lists \(list(listed)).
                """, bundle: .here)

            case let .noName(fileName):
                LocalizedStringResource("""
                \(fileName) says nothing about what the screenshot shows. Name it like \(example).
                """, bundle: .here)
            }
        }

        /// The device class this name asks for, when the only thing wrong with
        /// it is that the project does not list that device class.
        ///
        /// The file is named right and the image is the size that device class
        /// takes. Somebody who meant to start shipping on it can put it in the
        /// list and file this image as it is, so the front ends are handed the
        /// device class rather than the sentence about it.
        public var unlistedDeviceClass: DeviceClass? {
            guard case let .deviceNotListed(_, device, _) = self else { return nil }
            return device
        }

        /// Whether the name does not follow the inbox pattern.
        public var hasInvalidName: Bool {
            switch self {
            case .noLanguage, .twoLanguagesFit, .noDevice, .noName:
                true
            case .languageNotShipped, .deviceNotListed:
                false
            }
        }

        private func list(_ items: [String]) -> String {
            items.joined(separator: ", ")
        }

        /// A code as it looks in a file name.
        private func underscored(_ code: String?) -> String {
            ScreenshotNaming.token(of: code ?? "")
        }
    }

    // MARK: - Reading a name

    /// Works out where one waiting file goes, or why it cannot go anywhere.
    public static func read(_ fileName: String, config: ProjectConfig) -> Result<Parts, Refusal> {
        var parts = pieces(of: fileName)

        let locale: String
        switch readLanguage(&parts) {
        case let .code(code):
            guard config.writtenLocales.contains(code) else {
                return .failure(.languageNotShipped(
                    fileName: fileName, locale: code, shipped: config.writtenLocales
                ))
            }
            locale = code

        case let .language(language):
            let candidates = config.writtenLocales.filter {
                let listed = $0.lowercased()
                return listed == language || listed.hasPrefix("\(language)-")
            }
            switch candidates.count {
            case 1: locale = candidates[0]
            case 0:
                return .failure(.languageNotShipped(
                    fileName: fileName, locale: language, shipped: config.writtenLocales
                ))
            default:
                return .failure(.twoLanguagesFit(
                    fileName: fileName, language: language, candidates: candidates
                ))
            }

        case let .none(token):
            return .failure(.noLanguage(fileName: fileName, token: token))
        }

        guard let deviceClass = readDevice(&parts) else {
            return .failure(.noDevice(fileName: fileName, listed: config.deviceClasses))
        }
        guard config.resolvedDeviceClasses.contains(deviceClass) else {
            return .failure(.deviceNotListed(
                fileName: fileName, device: deviceClass, listed: config.deviceClasses
            ))
        }

        let imageName = parts.joined(separator: "-")
        guard imageName.isEmpty == false else { return .failure(.noName(fileName: fileName)) }

        return .success(Parts(locale: locale, deviceClass: deviceClass, imageName: imageName))
    }

    /// The part of a screenshot name that says what it shows.
    ///
    /// Strips the number, the device class, and the language, so the same
    /// screenshot can be found in every language. `03-shopping-iPhone-6.9-en_US`
    /// and `01-shopping-iPad-13-ja` are both `shopping`.
    ///
    /// This is what one screenshot is called across languages. It is never what
    /// a file is called: a file carries the whole name.
    public static func imageName(of fileName: String) -> String {
        var parts = pieces(of: fileName)
        _ = readLanguage(&parts)
        _ = readDevice(&parts)

        let name = parts.joined(separator: "-")
        return name.isEmpty ? ScreenshotRenumbering.nameWithoutNumber(of: fileName) : name
    }

    // MARK: - Writing a name

    /// What a screenshot in this slot is called.
    ///
    /// One rule, everywhere. The file on disk carries this name, App Store
    /// Connect is given this name with the image, and the next push matches on
    /// it. A name written any other way orphans the image it was uploaded as.
    public static func fileName(
        position: Int,
        imageName: String,
        deviceClass: DeviceClass,
        locale: String,
        extension pathExtension: String
    ) -> String {
        ScreenshotRenumbering.fileName(
            position: position,
            nameWithoutNumber: tail(imageName: imageName, deviceClass: deviceClass, locale: locale),
            extension: pathExtension
        )
    }

    /// The name without its number: what the screenshot shows, the device
    /// class, and the language.
    ///
    /// The number says where the image goes in the set, and it moves whenever
    /// the set is renumbered. Everything else stays, so this is the part two
    /// names are compared on.
    public static func tail(imageName: String, deviceClass: DeviceClass, locale: String) -> String {
        "\(imageName)-\(deviceClass.fileNameToken)-\(token(of: locale))"
    }

    /// A language as a file name writes it, such as `en_US`.
    ///
    /// The underscore keeps the language and the country in one piece, because
    /// the hyphen already separates the parts of the name.
    public static func token(of locale: String) -> String {
        locale.replacingOccurrences(of: "-", with: "_")
    }

    /// Whether this name says it belongs in this slot.
    ///
    /// Read at the door, in the inbox and in every tool, so a file that says
    /// one language cannot be filed under another. `nil` means it may come in.
    public static func reasonToRefuse(
        _ fileName: String,
        locale: String,
        deviceClass: DeviceClass,
        config: ProjectConfig
    ) -> String? {
        switch read(fileName, config: config) {
        case let .failure(refusal):
            return refusal.description

        case let .success(parts):
            if parts.locale != locale {
                return String(localized: LocalizedStringResource("""
                \(fileName) is for \(parts.locale), and this is the \(locale) set. \
                Name it like \(example).
                """, bundle: .here))
            }
            if parts.deviceClass != deviceClass {
                return String(localized: LocalizedStringResource("""
                \(fileName) is for \(parts.deviceClass.displayName), and this is the \
                \(deviceClass.displayName) set. Name it like \(example).
                """, bundle: .here))
            }
            return nil
        }
    }

    // MARK: - Taking the name apart

    /// The name without its number and its extension, cut at every hyphen.
    private static func pieces(of fileName: String) -> [String] {
        ScreenshotRenumbering.nameWithoutNumber(of: fileName)
            .split(separator: "-", omittingEmptySubsequences: false)
            .map(String.init)
    }

    private enum LanguageReading {
        /// A language App Store Connect knows by that exact code.
        case code(String)

        /// Two letters that name a language rather than a store code, such as
        /// `en`. Which `en` it is depends on what the project ships.
        case language(String)

        case none(token: String)
    }

    /// Takes the language off the end, and says what it found.
    ///
    /// Leaves the parts alone when it finds nothing, so a caller can carry on
    /// with a name that never had a language in it.
    private static func readLanguage(_ parts: inout [String]) -> LanguageReading {
        guard let last = parts.last else { return .none(token: "") }

        // `en-US` written with a hyphen arrives here as two parts. The pattern
        // uses `en_US` for that reason, and both are read the same way.
        if parts.count >= 2, let code = storeCode("\(parts[parts.count - 2])-\(last)") {
            parts.removeLast(2)
            return .code(code)
        }
        if let code = storeCode(last) {
            parts.removeLast()
            return .code(code)
        }

        let token = last.replacingOccurrences(of: "_", with: "-")
        if token.count == 2, token.allSatisfy(\.isLetter) {
            parts.removeLast()
            return .language(token.lowercased())
        }
        return .none(token: last)
    }

    /// The store code this token names, whatever case it was typed in.
    private static func storeCode(_ token: String) -> String? {
        let wanted = token.replacingOccurrences(of: "_", with: "-").lowercased()
        return StoreLocale.all.first { $0.code.lowercased() == wanted }?.code
    }

    /// Takes the device class off the end, and says which one it was.
    ///
    /// A device class id is two pieces, such as `iphone-6.9`, so the longest
    /// run is tried first. One and three are tried as well, because the ids
    /// live in one table and this should not have to change with it.
    private static func readDevice(_ parts: inout [String]) -> DeviceClass? {
        // iPhone Duo has an inner and an outer display, and people name them.
        // The pixel size already says which one it is, so the word goes.
        if let last = parts.last, foldDisplays.contains(last.lowercased()) {
            var withoutDisplay = Array(parts.dropLast())
            if readDevice(&withoutDisplay) == .iPhoneDuo {
                parts = withoutDisplay
                return .iPhoneDuo
            }
        }

        for count in stride(from: min(3, parts.count), through: 1, by: -1) {
            let token = parts.suffix(count).joined(separator: "-").lowercased()
            guard let deviceClass = DeviceClass.named(token) else { continue }
            parts.removeLast(count)
            return deviceClass
        }
        return nil
    }

    private static let foldDisplays: Set = ["inner", "outer"]
}

extension ScreenshotNaming.Refusal: CustomStringConvertible {
    public var description: String { String(localized: localizedStringResource) }
}
