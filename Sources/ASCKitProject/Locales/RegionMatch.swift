import Foundation

/// Turning Xcode's language codes into App Store locale codes.
///
/// The two lists do not agree. Xcode says `en`, and the App Store has four
/// Englishes. Xcode says `de`, and the App Store has one German. Where there is
/// one answer this gives it; where there are several it says which, and nothing
/// picks one on a person's behalf. A listing written in the wrong English is a
/// listing nobody notices is wrong.
public enum RegionMatch {
    /// What one Xcode region turned into.
    public enum Outcome: Sendable, Hashable {
        /// One App Store locale, and no doubt about it.
        case one(String)

        /// Several, and a person has to choose.
        case several([String])

        /// The App Store has no locale for this region at all.
        case none

        public var resolved: String? {
            if case let .one(code) = self { return code }
            return nil
        }

        public var choices: [String] {
            switch self {
            case let .one(code): [code]
            case let .several(codes): codes
            case .none: []
            }
        }
    }

    public static func outcome(for region: String) -> Outcome {
        // Already a code the App Store takes, such as `zh-Hans` or `pt-BR`.
        if StoreLocale.isKnown(region) { return .one(region) }

        let language = region.split(separator: "-").first.map(String.init) ?? region
        let matches = StoreLocale.all
            .filter { $0.code == language || $0.code.hasPrefix("\(language)-") }
            .map(\.code)

        return switch matches.count {
        case 0: .none
        case 1: .one(matches[0])
        default: .several(matches)
        }
    }

    /// Every region an Xcode project ships, with what each one became.
    ///
    /// Kept in the order Xcode listed them, so what a person sees matches what
    /// their project says.
    public static func outcomes(for regions: [String]) -> [(region: String, outcome: Outcome)] {
        regions.map { ($0, outcome(for: $0)) }
    }

    /// The regions that need somebody to choose, so a form can refuse to write
    /// anything until they have.
    public static func needingAChoice(in regions: [String]) -> [String] {
        outcomes(for: regions)
            .filter {
                if case .several = $0.outcome {
                    true
                } else {
                    false
                }
            }
            .map(\.region)
    }

    /// The locales that need no choosing, which is what a project with only
    /// unambiguous regions can be scaffolded with straight away.
    public static func resolved(in regions: [String]) -> [String] {
        outcomes(for: regions).compactMap(\.outcome.resolved)
    }
}
