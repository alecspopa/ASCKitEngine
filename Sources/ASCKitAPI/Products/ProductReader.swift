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
        let app = try await requireApp(bundleID: bundleID)

        async let purchases = readPurchases(appID: app.id)
        async let subscriptions = readSubscriptions(appID: app.id)

        let found = try await purchases + subscriptions.products
        let groups = try await subscriptions.groups
        async let withWords = includeWords ? readWords(for: found) : found
        async let groupsWithWords = includeWords ? readWords(for: groups) : groups
        // A refused retention read must not stop the purchases and prices.
        async let retention: Result<[RemoteRetentionMessage], any Error> = includeWords
            ? Result { try await retentionMessages(appID: app.id) }
            : .success([])

        var messages: [RemoteRetentionMessage] = []
        var failure: String?
        switch await retention {
        case let .success(read): messages = read
        case let .failure(error): failure = ErrorMessage.text(for: error)
        }

        return try await RemoteProducts(
            appID: app.id,
            products: withWords.sorted { $0.productID < $1.productID },
            groupNames: subscriptions.groupNames,
            groups: groupsWithWords.sorted { $0.referenceName < $1.referenceName },
            retentionMessages: messages.sorted { $0.referenceName < $1.referenceName },
            retentionReadFailure: failure
        )
    }

    // MARK: - One-time purchases

    private func readPurchases(appID: String) async throws -> [RemoteProduct] {
        try await inAppPurchases(appID: appID).compactMap { resource in
            guard let productID = resource.attributes?.productId else { return nil }
            let appleType = resource.attributes?.inAppPurchaseType
            return RemoteProduct(
                id: resource.id,
                productID: productID,
                // A kind added later keeps Apple's own word, so it reads as
                // itself and is reported rather than guessed at.
                kind: ProductKind(appleType: appleType)?.rawValue ?? appleType?.lowercased() ?? "unknown",
                referenceName: resource.attributes?.name,
                state: resource.attributes?.state,
                reviewNote: resource.attributes?.reviewNote,
                familySharable: resource.attributes?.familySharable
            )
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

        let found = try await groups.concurrentMap { group in
            let groupName = group.attributes?.referenceName
            return try await self.subscriptions(groupID: group.id).compactMap { resource -> RemoteProduct? in
                guard let productID = resource.attributes?.productId else { return nil }
                return RemoteProduct(
                    id: resource.id,
                    productID: productID,
                    kind: ProductKind.autoRenewableSubscription.rawValue,
                    referenceName: resource.attributes?.name,
                    state: resource.attributes?.state,
                    reviewNote: resource.attributes?.reviewNote,
                    familySharable: resource.attributes?.familySharable,
                    subscriptionGroup: groupName,
                    subscriptionPeriod: resource.attributes?.subscriptionPeriod
                )
            }
        }

        return SubscriptionRead(
            products: found.flatMap(\.self),
            groupNames: names.compactMapValues { $0 },
            groups: remoteGroups
        )
    }

    // MARK: - Words

    private func readWords(for products: [RemoteProduct]) async throws -> [RemoteProduct] {
        try await products.concurrentMap { product in
            guard let read = try await self.readWords(of: WordsOwner(product), parentID: product.id) else {
                // A product with no version has no words yet, and a read makes
                // none. The push refuses it and says to make the draft in App
                // Store Connect.
                return product
            }
            return product.with(version: read.version, words: Self.productWords(read.words))
        }
    }

    private func readWords(for groups: [RemoteSubscriptionGroup]) async throws -> [RemoteSubscriptionGroup] {
        try await groups.concurrentMap { group in
            guard let read = try await self.readWords(of: .subscriptionGroup, parentID: group.id) else {
                return group
            }
            return group.with(version: read.version, words: Self.groupWords(read.words))
        }
    }

    /// The words of the version a reader should show, or nil when the
    /// product holds no version yet.
    ///
    /// Two requests rather than one: the words hang off a version, so the
    /// version has to be found before they can be read.
    private func readWords(
        of owner: WordsOwner,
        parentID: String
    ) async throws -> (version: RemoteProductVersion, words: [Resource<ProductWordsAttributes>])? {
        let versions = try await wordsVersions(of: owner, parentID: parentID)
        guard let version = Self.wordsVersion(in: versions) else { return nil }
        return try await (Self.remoteVersion(version), words(of: owner, versionID: version.id))
    }

    private static func productWords(_ found: [Resource<ProductWordsAttributes>]) -> [RemoteProductLocalization] {
        found.compactMap { resource in
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

    private static func groupWords(_ found: [Resource<ProductWordsAttributes>]) -> [RemoteGroupLocalization] {
        found.compactMap { resource in
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
}

public extension ASCClient {
    // MARK: - A new draft

    /// Makes a new draft of this product's words, and reads the words it
    /// copied.
    ///
    /// The copies have ids of their own, and a change to a language names the
    /// row in the new draft.
    func newWordsDraft(for product: RemoteProduct) async throws -> RemoteProduct {
        let owner = WordsOwner(product)
        let version = try await createWordsVersion(of: owner, parentID: product.id)
        let found = try await words(of: owner, versionID: version.id)
        return product.with(version: Self.remoteVersion(version), words: Self.productWords(found))
    }

    func newWordsDraft(for group: RemoteSubscriptionGroup) async throws -> RemoteSubscriptionGroup {
        let version = try await createWordsVersion(of: .subscriptionGroup, parentID: group.id)
        let found = try await words(of: .subscriptionGroup, versionID: version.id)
        return group.with(version: Self.remoteVersion(version), words: Self.groupWords(found))
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
