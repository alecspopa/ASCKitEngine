import ASCKitAPI
import Foundation

/// Turns what App Store Connect holds into product files.
///
/// How a project starts from an app that already sells things. It writes over
/// nothing without being told to, because what is on disk may be a translation
/// somebody is still working on.
public enum ProductSnapshot {
    public struct Outcome: Sendable {
        public let written: [String]

        /// Already on disk, so left exactly as it was.
        public let left: [String]

        /// Products whose id cannot be a file name.
        public let refused: [(productID: String, reason: String)]

        /// Subscription group files written, by reference name.
        public var writtenGroups: [String] = []

        public var isEmpty: Bool {
            written.isEmpty && left.isEmpty && refused.isEmpty && writtenGroups.isEmpty
        }
    }

    public static func write(
        _ remote: RemoteProducts,
        to project: Project,
        overwrite: Bool = false
    ) throws -> Outcome {
        let existing = ProductStore.load(in: project)

        var written: [String] = []
        var left: [String] = []
        var refused: [(productID: String, reason: String)] = []

        for product in remote.products.sorted(by: { $0.productID < $1.productID }) {
            if let reason = ProductStore.reasonToRefuse(productID: product.productID) {
                refused.append((product.productID, reason))
                continue
            }
            guard overwrite || existing.products[product.productID] == nil else {
                left.append(product.productID)
                continue
            }

            try ContentWriter.writeProduct(
                make(product, config: project.config),
                in: project
            )
            written.append(product.productID)
        }

        // A group with no words on the store gets no file. The person makes
        // one on the group page, and an empty file would say nothing.
        var writtenGroups: [String] = []
        for group in remote.groups {
            guard ProductStore.reasonToRefuse(groupName: group.referenceName) == nil else { continue }
            guard overwrite || existing.groups[group.referenceName] == nil else { continue }
            let made = make(group, config: project.config)
            guard made.localizations.isEmpty == false else { continue }

            try ContentWriter.writeSubscriptionGroup(made, in: project)
            writtenGroups.append(group.referenceName)
        }

        return Outcome(
            written: written, left: left, refused: refused, writtenGroups: writtenGroups
        )
    }

    /// One group file, from what the store holds. `needs_human` for the same
    /// reason a product file is.
    public static func make(_ remote: RemoteSubscriptionGroup, config: ProjectConfig) -> SubscriptionGroup {
        var words: [String: SubscriptionGroup.Localization] = [:]
        for (locale, written) in remote.localizations where config.writtenLocales.contains(locale) {
            words[locale] = SubscriptionGroup.Localization(
                name: written.name,
                customAppName: written.customAppName
            )
        }
        return SubscriptionGroup(
            referenceName: remote.referenceName,
            status: .needsHuman,
            localizations: words
        )
    }

    /// One product file, from what the store holds.
    ///
    /// The status is `needs_human`. The words are real and already on the
    /// store, so nothing here is a draft, but nobody has read them through
    /// ASCKit and a file that arrives by itself saying `approved` is a file
    /// that gets published without anyone looking.
    ///
    /// No price plan. Reading what a product costs everywhere means reading its
    /// whole price ladder, which is thousands of rows per product, so a plan is
    /// something you write rather than something a pull guesses at.
    public static func make(_ remote: RemoteProduct, config: ProjectConfig) -> Product {
        var words: [String: Product.Localization] = [:]
        for (locale, written) in remote.localizations where config.writtenLocales.contains(locale) {
            words[locale] = Product.Localization(
                name: written.name,
                description: written.description
            )
        }

        return Product(
            productID: remote.productID,
            kind: remote.kind,
            referenceName: remote.referenceName,
            subscriptionGroup: remote.subscriptionGroup,
            subscriptionPeriod: remote.subscriptionPeriod,
            familySharable: remote.familySharable,
            status: .needsHuman,
            reviewNote: remote.reviewNote,
            price: nil,
            localizations: words
        )
    }

    /// Languages the store holds for a product that this project does not ship.
    ///
    /// Worth saying out loud rather than dropping quietly: it usually means the
    /// locale list is short, not that the store is wrong.
    public static func unshippedLocales(
        in remote: RemoteProducts,
        config: ProjectConfig
    ) -> [String] {
        let held = Set(remote.products.flatMap(\.localizations.keys))
        return held.subtracting(config.locales).sorted()
    }
}
