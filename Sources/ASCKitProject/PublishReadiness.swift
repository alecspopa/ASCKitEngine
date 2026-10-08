import Foundation

/// Which parts of a push can go, and what to say above the button.
///
/// In the library rather than in the window, for the reason
/// `ChangePlanFormatter` is there: these are rules about a plan, and the
/// wording of a refusal is worth a test. Reads no files and no network, so a
/// view can ask on every redraw.
public enum PublishReadiness {
    /// Everything a refusal turns on.
    public struct Inputs: Sendable {
        public var plan: ChangePlan?

        /// The version App Store Connect moved to with no folder here. Holds up
        /// the listing and nothing else, because an in-app purchase belongs to
        /// no version.
        public var versionToCreate: String?

        /// Images App Store Connect has not finished with.
        ///
        /// Almost always these are the images a push put there a moment ago.
        public var stillArrivingImages: Int

        public var agreedToRises: Bool

        public init(
            plan: ChangePlan?,
            versionToCreate: String? = nil,
            stillArrivingImages: Int = 0,
            agreedToRises: Bool = false
        ) {
            self.plan = plan
            self.versionToCreate = versionToCreate
            self.stillArrivingImages = stillArrivingImages
            self.agreedToRises = agreedToRises
        }
    }

    public static func availability(given inputs: Inputs) -> [PublishPart: PublishAvailability] {
        var states: [PublishPart: PublishAvailability] = [:]
        for part in PublishPart.pushOrder {
            states[part] = availability(of: part, given: inputs)
        }
        return states
    }

    /// The reasons in order, first match wins.
    public static func availability(
        of part: PublishPart,
        given inputs: Inputs
    ) -> PublishAvailability {
        guard let plan = inputs.plan else {
            return .blocked(String(
                localized: "Nothing has been read yet. Read App Store Connect first.", bundle: .module
            ))
        }

        if let version = inputs.versionToCreate, needsAVersionFolder(part) {
            return .blocked(String(localized: """
            App Store Connect is on version \(version), and there is no \
            folder for it here.
            """, bundle: .module))
        }

        // A locked version holds up the listing and nothing else, because an
        // in-app purchase belongs to no version.
        let blocked = plan.blocked(part)
        if let first = blocked.first {
            let rest = blocked.count - 1
            guard rest > 0 else {
                return .blocked(String(
                    localized: "\(first.reason) Affects \(first.affects).", bundle: .module
                ))
            }
            return .blocked(String(
                localized: "\(first.reason) Affects \(first.affects). And \(rest) more.", bundle: .module
            ))
        }

        // Before the two agreements, so a plan with no price change never says
        // that prices would go up.
        guard plan.changes(part) else { return .nothingToDo }

        // An asset still processing can still fail, and then its slot plans
        // again. Pushing before it settles places an asset that may not stay.
        if part == .screenshots, inputs.stillArrivingImages > 0 {
            let images = inputs.stillArrivingImages
            return .blocked(String(localized: """
            App Store Connect has not finished with \(images) images. \
            Read it again in a moment.
            """, bundle: .module))
        }

        if part == .prices, plan.priceRises.isEmpty == false, inputs.agreedToRises == false {
            let rises = plan.priceRises.count
            return .blocked(String(
                localized: "\(rises) prices would go up. Read them and tick the box.", bundle: .module
            ))
        }

        return .ready(ChangePlanFormatter.count(of: part, in: plan) ?? "")
    }

    /// What to say above the button, or nil when nothing is ticked.
    ///
    /// A push is not an edit that can be taken back, so the first sentence says
    /// so whatever is ticked. The sentences after it are the two things a
    /// person cannot get back at all.
    public static func notice(for parts: PublishParts, given inputs: Inputs) -> String? {
        guard parts.isEmpty == false else { return nil }
        var sentences = [String(
            localized: "Push writes over what App Store Connect holds now.", bundle: .module
        )]

        if parts.contains(.screenshots) {
            sentences.append(String(
                localized: "A screenshot taken off a set stays in the app's asset library.",
                bundle: .module
            ))
        }

        let rises = inputs.plan?.priceRises.count ?? 0
        if parts.contains(.prices), rises > 0 {
            sentences.append(String(
                localized: "\(rises) prices go up, and a rise cannot be taken back.", bundle: .module
            ))
        }
        return sentences.joined(separator: " ")
    }

    /// The listing halves, which have nothing to go from until the folder for
    /// the version App Store Connect moved to exists.
    private static func needsAVersionFolder(_ part: PublishPart) -> Bool {
        part == .appInformation || part == .screenshots
    }
}
