import Foundation

/// How far a push has got, counted in the steps a person can watch go by.
///
/// A step is one thing a pusher says it is starting: a language, an in-app
/// purchase, an image. Every pusher reports one, so a bar built on this counts
/// the same thing whichever parts one press writes.
///
/// The total comes off the plan before anything is written, and that is the
/// plan the sheet showed. So the bar measures the press somebody agreed to.
public struct PushProgress: Sendable, Equatable {
    /// How many steps each ticked part has to report.
    private let expected: [PublishPart: Int]

    /// Parts that have run, whatever they said while they ran.
    private var done: Set<PublishPart> = []

    /// Steps that have started.
    ///
    /// A pusher speaks before it works and says nothing after, so a step counts
    /// as it begins. The last step of a push is therefore on screen while it
    /// runs, which is the one a person waits on.
    public private(set) var completed = 0

    /// The step that started last, in the pusher's own words. Nil until the
    /// first one.
    public private(set) var step: String?

    public var total: Int { expected.values.reduce(0, +) }

    public init(_ parts: PublishParts, in plan: ChangePlan) {
        expected = Dictionary(
            uniqueKeysWithValues: parts.map { ($0, Self.steps(for: $0, in: plan)) }
        )
    }

    /// Counts a step, and says what it is.
    ///
    /// Never past the total. The plan counts what a push is about to do, and
    /// App Store Connect can hold one image more than the plan expected, so the
    /// count is what the bar shows and not what it trusts.
    public mutating func start(_ step: String) {
        self.step = step
        completed = min(completed + 1, total)
    }

    /// A part is over, so everything it had to do is done.
    ///
    /// A step can go by without a word. A language with no file behind it is
    /// skipped in silence, and the bar would then sit short of the end for the
    /// rest of the push. This puts it where the finished parts say it is.
    public mutating func finish(_ part: PublishPart) {
        done.insert(part)
        completed = max(completed, done.reduce(0) { $0 + (expected[$1] ?? 0) })
    }

    // MARK: - What a part has to do

    /// How many steps one part reports, off the plan it would write.
    public static func steps(for part: PublishPart, in plan: ChangePlan) -> Int {
        switch part {
        case .appInformation: plan.changedTextLocales
        case .purchases: productTextSteps(in: plan)
        case .prices: plan.changedPricedProducts
        case .screenshots: screenshotSteps(in: plan)
        }
    }

    /// The words of a purchase go out one language at a time, and the name and
    /// the description of that language go together in one request.
    private static func productTextSteps(in plan: ChangePlan) -> Int {
        var seen: Set<String> = []
        let products = plan.productTextChanges.count {
            seen.insert("\($0.productID)|\($0.locale)").inserted
        }
        let groups = plan.groupTextChanges.count {
            seen.insert("group|\($0.group)|\($0.locale)").inserted
        }
        return products + groups
    }

    /// A file goes up once however many slots use it. A slot then takes its
    /// placements off, makes the new ones and sets the order.
    private static func screenshotSteps(in plan: ChangePlan) -> Int {
        let slots = plan.screenshotPlans.map(\.library) + plan.previewPlans.map(\.library)
            + plan.creativePlans.map(\.library)
        let changing = slots.filter { $0.isUnchanged == false }
        let uploads = Set(changing.flatMap { slot in
            zip(slot.wanted, slot.checksums).compactMap { $0.0 == nil ? $0.1 : nil }
        }).count
        return uploads + changing.reduce(0) { total, slot in
            total + (slot.toRemove.isEmpty ? 0 : 1) + (slot.placementsToAdd > 0 ? 1 : 0)
                + (slot.wanted.count > 1 ? 1 : 0)
        }
    }
}
