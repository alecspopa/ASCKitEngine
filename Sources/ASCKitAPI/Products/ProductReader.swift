import Foundation

public extension ASCClient {
    /// Reads every in-app purchase an app has, with its words.
    ///
    /// Two kinds of product arrive by two different routes, and a subscription
    /// takes an extra hop because it hangs off a group rather than off the app.
    /// Both routes run at once, and so does every product's words, because a
    /// catalogue of twenty products is otherwise twenty round trips queueing up
    /// behind each other.
    ///
    /// Prices are not read here. A price ladder belongs to one product and runs
    /// to thousands of rows, so it is asked for when somebody wants to see a
    /// price rather than every time a window opens.
    func products(bundleID: String, includeWords: Bool = true) async throws -> RemoteProducts {
        guard let app = try await app(bundleID: bundleID) else {
            throw ListingError.noSuchApp(bundleID: bundleID)
        }

        async let purchases = readPurchases(appID: app.id)
        async let subscriptions = readSubscriptions(appID: app.id)

        let found = try await purchases + subscriptions.products
        let withWords = includeWords ? try await readWords(for: found) : found
        let groups = try await subscriptions.groups
        let groupsWithWords = includeWords ? try await readGroupWords(for: groups) : groups

        return try await RemoteProducts(
            appID: app.id,
            products: withWords.sorted { $0.productID < $1.productID },
            groupNames: subscriptions.groupNames,
            groups: groupsWithWords.sorted { $0.referenceName < $1.referenceName }
        )
    }

    // MARK: - One-time purchases

    private func readPurchases(appID: String) async throws -> [RemoteProduct] {
        try await inAppPurchases(appID: appID).compactMap { resource in
            guard let productID = resource.attributes?.productId else { return nil }
            return RemoteProduct(
                id: resource.id,
                productID: productID,
                kind: Self.kind(fromAppleType: resource.attributes?.inAppPurchaseType),
                referenceName: resource.attributes?.name,
                state: resource.attributes?.state,
                reviewNote: resource.attributes?.reviewNote,
                familySharable: resource.attributes?.familySharable
            )
        }
    }

    /// Apple writes the kind in capitals with underscores. ASCKit writes it in
    /// lower case, because that is what goes in a file somebody reads.
    private static func kind(fromAppleType written: String?) -> String {
        switch written {
        case "CONSUMABLE": "consumable"
        case "NON_CONSUMABLE": "non_consumable"
        case "NON_RENEWING_SUBSCRIPTION": "non_renewing_subscription"
        // Anything else keeps Apple's own word, so a kind added later reads as
        // itself and is reported rather than guessed at.
        default: written?.lowercased() ?? "unknown"
        }
    }

    // MARK: - Subscriptions

    private struct SubscriptionRead: Sendable {
        let products: [RemoteProduct]
        let groupNames: [String: String]
        let groups: [RemoteSubscriptionGroup]
    }

    private func readSubscriptions(
        appID: String
    ) async throws -> SubscriptionRead {
        let groups = try await subscriptionGroups(appID: appID)
        var names: [String: String] = [:]
        for group in groups {
            names[group.id] = group.attributes?.referenceName
        }
        let remoteGroups = groups.compactMap { group in
            group.attributes?.referenceName.map {
                RemoteSubscriptionGroup(id: group.id, referenceName: $0)
            }
        }

        let found = try await withThrowingTaskGroup(of: [RemoteProduct].self) { tasks in
            for group in groups {
                let groupName = group.attributes?.referenceName
                tasks.addTask {
                    try await self.subscriptions(groupID: group.id).compactMap { resource in
                        guard let productID = resource.attributes?.productId else { return nil }
                        return RemoteProduct(
                            id: resource.id,
                            productID: productID,
                            kind: "auto_renewable_subscription",
                            referenceName: resource.attributes?.name,
                            state: resource.attributes?.state,
                            reviewNote: resource.attributes?.reviewNote,
                            familySharable: resource.attributes?.familySharable,
                            subscriptionGroup: groupName,
                            subscriptionPeriod: resource.attributes?.subscriptionPeriod
                        )
                    }
                }
            }
            var collected: [RemoteProduct] = []
            for try await batch in tasks {
                collected += batch
            }
            return collected
        }

        return SubscriptionRead(
            products: found,
            groupNames: names.compactMapValues { $0 },
            groups: remoteGroups
        )
    }

    // MARK: - Words

    private func readGroupWords(
        for groups: [RemoteSubscriptionGroup]
    ) async throws -> [RemoteSubscriptionGroup] {
        try await withThrowingTaskGroup(of: RemoteSubscriptionGroup.self) { tasks in
            for group in groups {
                tasks.addTask { try await self.withWords(group) }
            }
            var collected: [RemoteSubscriptionGroup] = []
            for try await one in tasks {
                collected.append(one)
            }
            return collected
        }
    }

    /// The words a group holds, out of the version they live in.
    ///
    /// Two requests rather than one: the words hang off a version now, so the
    /// version has to be found before they can be read.
    private func withWords(
        _ group: RemoteSubscriptionGroup
    ) async throws -> RemoteSubscriptionGroup {
        let versions = try await subscriptionGroupVersions(groupID: group.id)

        // A group with no version has no words yet, and a read makes none.
        guard let version = Self.wordsVersion(in: versions) else { return group }

        let found = try await groupWords(inVersion: version.id)
        return group.with(version: Self.remoteVersion(version), words: found)
    }

    private func groupWords(
        inVersion versionID: String
    ) async throws -> [RemoteGroupLocalization] {
        try await subscriptionGroupLocalizations(versionID: versionID)
            .compactMap { resource -> RemoteGroupLocalization? in
                guard let locale = resource.attributes?.locale else { return nil }
                return RemoteGroupLocalization(
                    id: resource.id,
                    locale: locale,
                    name: resource.attributes?.name,
                    customAppName: resource.attributes?.customAppName,
                    state: resource.attributes?.state
                )
            }
    }

    /// A subscription's words and a one-time purchase's words come from two
    /// different endpoints holding the same two fields.
    private func readWords(for products: [RemoteProduct]) async throws -> [RemoteProduct] {
        try await withThrowingTaskGroup(of: RemoteProduct.self) { tasks in
            for product in products {
                tasks.addTask { try await self.withWords(product) }
            }
            var collected: [RemoteProduct] = []
            for try await one in tasks {
                collected.append(one)
            }
            return collected
        }
    }

    private func withWords(_ product: RemoteProduct) async throws -> RemoteProduct {
        let versions = product.isAutoRenewable
            ? try await subscriptionVersions(subscriptionID: product.id)
            : try await inAppPurchaseVersions(purchaseID: product.id)

        // A product with no version has no words yet, and a read makes none.
        // The push refuses it and says to make the draft in App Store Connect.
        guard let version = Self.wordsVersion(in: versions) else { return product }

        let found = try await words(of: product, inVersion: version.id)
        return product.with(version: Self.remoteVersion(version), words: found)
    }

    /// The two endpoints hand back two types carrying the same two fields, so
    /// each branch maps its own.
    private func words(
        of product: RemoteProduct,
        inVersion versionID: String
    ) async throws -> [RemoteProductLocalization] {
        if product.isAutoRenewable {
            return try await subscriptionLocalizations(versionID: versionID)
                .compactMap { resource in
                    guard let locale = resource.attributes?.locale else { return nil }
                    return RemoteProductLocalization(
                        id: resource.id,
                        locale: locale,
                        name: resource.attributes?.name,
                        description: resource.attributes?.description,
                        state: resource.attributes?.state
                    )
                }
        }
        return try await inAppPurchaseLocalizations(versionID: versionID)
            .compactMap { resource in
                guard let locale = resource.attributes?.locale else { return nil }
                return RemoteProductLocalization(
                    id: resource.id,
                    locale: locale,
                    name: resource.attributes?.name,
                    description: resource.attributes?.description,
                    state: resource.attributes?.state
                )
            }
    }
}

public extension ASCClient {
    // MARK: - A new draft

    /// Makes a new draft of this product's words, and reads the words it
    /// copied.
    ///
    /// The copies have ids of their own, and a change to a language names the
    /// row in the new draft.
    func newWordsDraft(for product: RemoteProduct) async throws -> RemoteProduct {
        let version = try await createWordsVersion(
            of: product.isAutoRenewable ? .subscription : .inAppPurchase,
            parentID: product.id
        )
        let found = try await words(of: product, inVersion: version.id)
        return product.with(version: Self.remoteVersion(version), words: found)
    }

    func newWordsDraft(for group: RemoteSubscriptionGroup) async throws -> RemoteSubscriptionGroup {
        let version = try await createWordsVersion(of: .subscriptionGroup, parentID: group.id)
        let found = try await groupWords(inVersion: version.id)
        return group.with(version: Self.remoteVersion(version), words: found)
    }
}

extension ASCClient {
    /// The value the rest of ASCKit reads a version through.
    static func remoteVersion(
        _ version: Resource<ProductVersionAttributes>
    ) -> RemoteProductVersion {
        RemoteProductVersion(
            id: version.id,
            number: version.attributes?.version,
            state: version.attributes?.state
        )
    }

    /// One row per language.
    ///
    /// A read used to hand back two rows for a language a product had already
    /// sold in, and the draft had to be picked out by state. Those two rows
    /// were two versions all along. The read is scoped to one version now, so
    /// the store answers with one row per language and `wordsVersion(in:)` is
    /// the only place that chooses between a draft and the live words.
    ///
    /// The first row still wins if Apple ever sends two. A read that keeps the
    /// first beats a read that traps on something the store sent.
    static func byLocale<Row>(
        _ found: [Row],
        key: (Row) -> String
    ) -> [String: Row] {
        Dictionary(found.map { (key($0), $0) }, uniquingKeysWith: { first, _ in first })
    }
}
