import ASCKitAPI
import Foundation

/// Where the subscription group names on disk and the ones on App Store
/// Connect have stopped agreeing.
///
/// A group file holds no id. Its name is the only link to its group, and a
/// person can change that name on App Store Connect. App Store Connect is the
/// source of truth, so the files follow it.
///
/// A product id never changes. So the subscriptions of a group say what App
/// Store Connect calls the group now.
public enum SubscriptionGroupDrift {
    public struct Rename: Sendable, Equatable {
        public let from: String
        public let to: String

        /// Every subscription file that gives the old name, by product id.
        public let productIDs: [String]

        public init(from: String, to: String, productIDs: [String]) {
            self.from = from
            self.to = to
            self.productIDs = productIDs
        }
    }

    public struct Outcome: Sendable, Equatable {
        public let renames: [Rename]

        /// Group files with a name App Store Connect does not hold and no
        /// subscription gives. Nothing says what the group is called now.
        public let gone: [String]

        public var agrees: Bool { renames.isEmpty && gone.isEmpty }

        public init(renames: [Rename] = [], gone: [String] = []) {
            self.renames = renames
            self.gone = gone
        }
    }

    /// Reads no file and writes none.
    public static func compare(local: ProductCatalog, remote: RemoteProducts) -> Outcome {
        let onStore = Set(remote.groups.map(\.referenceName))
        let products = remote.byProductID

        var renames: [Rename] = []
        var gone: [String] = []

        for name in local.groupNames where onStore.contains(name) == false {
            let subscriptions = local.subscriptions(in: name)
            guard subscriptions.isEmpty == false else {
                gone.append(name)
                continue
            }

            // More than one answer is a group somebody split, and this cannot
            // say which part keeps the words. The plan goes on blocking it.
            let answers = Set(subscriptions.compactMap { products[$0.productID]?.subscriptionGroup })
            guard answers.count == 1, let target = answers.first,
                  ProductStore.reasonToRefuse(groupName: target) == nil
            else { continue }

            renames.append(Rename(
                from: name, to: target, productIDs: subscriptions.map(\.productID)
            ))
        }
        return Outcome(renames: renames, gone: gone)
    }

    // MARK: - Following

    /// What `follow` did to the files.
    public struct Followed: Sendable, Equatable {
        public let renamed: [Rename]

        /// Group files now in the Trash, by name.
        public let trashed: [String]

        /// Group files made from what App Store Connect holds, by name.
        public let written: [String]

        public var isEmpty: Bool { renamed.isEmpty && trashed.isEmpty && written.isEmpty }
    }

    /// Makes the files say what App Store Connect says.
    ///
    /// A renamed group keeps its file, so its status and its words stay. The
    /// Trash rather than a delete for a file that goes, because it may hold
    /// the only copy of a translation.
    ///
    /// Safe to run again after it stopped half way. Each step looks at the
    /// files as they are now.
    @discardableResult
    public static func follow(
        _ drift: Outcome,
        from remote: RemoteProducts,
        in project: Project
    ) throws -> Followed {
        let catalog = ProductStore.load(in: project)

        // From the folder and never from `fileExists`. On a volume that
        // ignores case, Premium.json answers for premium.json.
        var groupFiles = Set(catalog.groups.keys).union(catalog.unreadableGroups.keys)
        var trashed: [String] = []

        for rename in drift.renames {
            for productID in rename.productIDs {
                guard var product = catalog.products[productID] else { continue }
                product.subscriptionGroup = rename.to
                try ContentWriter.writeProduct(product, in: project)
            }

            guard groupFiles.contains(rename.from) else { continue }
            let old = project.subscriptionGroupURL(name: rename.from)
            let new = project.subscriptionGroupURL(name: rename.to)
            groupFiles.remove(rename.from)

            if groupFiles.contains(rename.to) {
                // A file a person wrote under the new name is the newer of the
                // two, so it stays. A copy of the store holds nothing of
                // theirs, so it makes way.
                guard isCopyOfStore(catalog.groups[rename.to], remote, project.config) else {
                    try FileManager.default.trashItem(at: old, resultingItemURL: nil)
                    trashed.append(rename.from)
                    continue
                }
                try FileManager.default.trashItem(at: new, resultingItemURL: nil)
            }

            try FileManager.default.moveItem(at: old, to: new)
            groupFiles.insert(rename.to)
        }

        for name in drift.gone where groupFiles.contains(name) {
            try FileManager.default.trashItem(
                at: project.subscriptionGroupURL(name: name), resultingItemURL: nil
            )
            groupFiles.remove(name)
            trashed.append(name)
        }

        return try Followed(
            renamed: drift.renames,
            trashed: trashed,
            written: drift.gone.isEmpty ? [] : takeIn(remote, in: project)
        )
    }

    /// Whether a group file is what a pull wrote and nobody changed since.
    ///
    /// A pull before the rename was followed writes the new name beside the
    /// old one. That file must not push aside the one with a person's words.
    private static func isCopyOfStore(
        _ group: SubscriptionGroup?,
        _ remote: RemoteProducts,
        _ config: ProjectConfig
    ) -> Bool {
        guard let group, let held = remote.groupsByName[group.referenceName] else { return false }
        return group == ProductSnapshot.make(held, config: config)
    }

    /// Gives a file to every group App Store Connect holds that nothing here
    /// names, so the name a lost group has now is on screen.
    ///
    /// A group with no words gets a file too. `ProductSnapshot` leaves that
    /// one out, but no subscription names this group, so only a file shows it.
    private static func takeIn(_ remote: RemoteProducts, in project: Project) throws -> [String] {
        let catalog = ProductStore.load(in: project)
        let named = Set(catalog.groupNames).union(catalog.unreadableGroups.keys)

        var written: [String] = []
        for group in remote.groups where named.contains(group.referenceName) == false {
            guard ProductStore.reasonToRefuse(groupName: group.referenceName) == nil else { continue }

            try ContentWriter.writeSubscriptionGroup(
                ProductSnapshot.make(group, config: project.config), in: project
            )
            written.append(group.referenceName)
        }
        return written
    }
}
