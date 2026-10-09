import Foundation

/// One part of a push, as a person ticks it and as a report names it.
///
/// A push writes four separate things, and they fail in four separate ways. The
/// name lives here rather than in the window, so the checkbox and the heading
/// over that part's report cannot drift apart.
public enum PublishPart: String, Sendable, CaseIterable, Identifiable, Hashable {
    /// The listing text: the name, the description, what is new, the keywords.
    case appInformation
    /// The names and descriptions of the in-app purchases.
    case purchases
    case prices
    case screenshots
    /// The images of the treatments in the draft Product Page Optimization
    /// tests. They take a reading of their own, apart from the listing.
    case productPageOptimization

    public var id: String { rawValue }

    /// The name on the checkbox, and the heading over this part's report.
    ///
    /// "App Information" rather than "Text", because that is what the page in
    /// the project window is called, and a person has to know which text goes.
    public var heading: LocalizedStringResource {
        switch self {
        case .appInformation: LocalizedStringResource("App Information", bundle: .here)
        case .purchases: LocalizedStringResource("In-App Purchases", bundle: .here)
        case .prices: LocalizedStringResource("Prices", bundle: .here)
        case .screenshots: LocalizedStringResource("Screenshots", bundle: .here)
        case .productPageOptimization: LocalizedStringResource("Product Page Optimization", bundle: .here)
        }
    }

    /// What ticking this writes, for the row's help.
    public var summary: LocalizedStringResource {
        switch self {
        case .appInformation:
            LocalizedStringResource(
                "The name, the subtitle, the description, the keywords and what is new.", bundle: .here
            )
        case .purchases:
            LocalizedStringResource("The names and descriptions of the in-app purchases.", bundle: .here)
        case .prices:
            LocalizedStringResource("What every in-app purchase costs in every country.", bundle: .here)
        case .screenshots:
            LocalizedStringResource(
                "The screenshots, previews and header art. Each file goes up once, then is placed.", bundle: .here
            )
        case .productPageOptimization:
            LocalizedStringResource("The images of the treatments in the draft tests.", bundle: .here)
        }
    }

    /// The order one press writes them in.
    ///
    /// Words first, because they are the cheapest to put back. Money next. The
    /// images last, because they take the longest, and a failure there is
    /// worth reading a finished report about. The test images go after the
    /// listing, because the listing is what every visitor sees.
    public static let pushOrder: [PublishPart] = [
        .appInformation, .purchases, .prices, .screenshots, .productPageOptimization
    ]

    /// Whether this part writes off a reading of the listing. The test images
    /// write off a reading of the draft tests.
    public var readsListing: Bool { self != .productPageOptimization }
}

/// The parts one press writes.
public typealias PublishParts = Set<PublishPart>
