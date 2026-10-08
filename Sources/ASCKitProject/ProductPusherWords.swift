import ASCKitAPI
import Foundation

/// Writing the names and descriptions of the in-app purchases.
///
/// The prices are in `ProductPusher.swift`. The two halves share the client
/// and nothing else: one is an edit and the other is money.
public extension ProductPusher {
    /// What a write of the words did.
    struct TextResult: Sendable {
        public var written: [String] = []
        public var failed: [Failure] = []

        /// The draft each product's words went into.
        ///
        /// A version is what App Review looks at, so the one a push wrote to is
        /// what somebody looks for in App Store Connect afterwards. A new draft
        /// the push made is here too.
        public var drafts: [Draft] = []

        /// The bodies a dry run would have sent, in the order it would have
        /// sent them.
        public var wouldSend: [String] = []

        public var isCompleteSuccess: Bool { failed.isEmpty }
    }

    /// The version one product's words were written into.
    struct Draft: Sendable, Hashable {
        /// The product id, or a group's reference name, the way `Failure` does
        /// it.
        public let productID: String

        public let versionID: String

        /// Apple's counter, 1 for the first.
        public let number: Int?
    }
}

extension ProductPusher {
    /// One language failing does not stop the rest, and one product failing
    /// does not stop the others.
    ///
    /// A product's words live in a version. When review is done with that
    /// version, this makes a new draft first, the way the web page of App Store
    /// Connect does. A product with no version, or with a version that review
    /// has now, is refused whole, and none of its languages are attempted.
    func pushText(
        _ plan: ChangePlan,
        to remote: RemoteProducts,
        dryRun: Bool = false,
        progress: (@Sendable (String) -> Void)? = nil
    ) async -> TextResult {
        var result = TextResult()
        let byProductID = remote.byProductID

        for (productID, changes) in group(plan.productTextChanges) {
            guard let product = byProductID[productID] else {
                result.failed.append(Failure(
                    productID: productID,
                    what: "",
                    reason: "App Store Connect no longer has this in-app purchase."
                ))
                continue
            }

            guard let product = await writable(
                product, locales: changes.keys.sorted(), dryRun: dryRun,
                progress: progress, into: &result
            ),
                let draft = product.version
            else { continue }

            for locale in changes.keys.sorted() {
                guard let fields = changes[locale] else { continue }
                progress?("\(productID), \(locale)")

                do {
                    if dryRun {
                        let body = try preview(
                            fields, locale: locale, of: product, in: draft
                        )
                        result.wouldSend.append(body)
                        continue
                    }
                    try await write(fields, locale: locale, of: product, in: draft)
                    result.written.append("\(productID) \(locale)")
                } catch {
                    result.failed.append(Failure(
                        productID: productID,
                        what: locale,
                        reason: ErrorMessage.text(for: error)
                    ))
                }
            }
        }

        await pushGroupWords(plan, to: remote, dryRun: dryRun,
                             progress: progress, into: &result)
        return result
    }

    /// The same work for a subscription group's words.
    ///
    /// Its own function only because `pushText` is at the length SwiftLint
    /// allows.
    private func pushGroupWords(
        _ plan: ChangePlan,
        to remote: RemoteProducts,
        dryRun: Bool,
        progress: (@Sendable (String) -> Void)?,
        into result: inout TextResult
    ) async {
        let groupsByName = remote.groupsByName

        for (groupName, changes) in group(plan.groupTextChanges) {
            guard let group = groupsByName[groupName] else {
                result.failed.append(Failure(
                    productID: groupName,
                    what: "",
                    reason: "App Store Connect no longer has this subscription group."
                ))
                continue
            }

            guard let group = await writable(
                group, locales: changes.keys.sorted(), dryRun: dryRun,
                progress: progress, into: &result
            ),
                let draft = group.version
            else { continue }

            for locale in changes.keys.sorted() {
                guard let fields = changes[locale] else { continue }
                progress?("\(groupName), \(locale)")

                do {
                    if dryRun {
                        let body = try preview(
                            fields, locale: locale, of: group, in: draft
                        )
                        result.wouldSend.append(body)
                        continue
                    }
                    try await write(fields, locale: locale, of: group, in: draft)
                    result.written.append("\(groupName) \(locale)")
                } catch {
                    result.failed.append(Failure(
                        productID: groupName,
                        what: locale,
                        reason: ErrorMessage.text(for: error)
                    ))
                }
            }
        }
    }

    // MARK: - The draft

    /// The version id a dry run writes into when a real run would make a new
    /// draft. The real id exists only after the draft is made.
    static let newDraftID = "${new-draft}"

    /// The product whose draft takes the words, or nil with the refusal
    /// already recorded.
    ///
    /// The new draft copies the words of the version before it. Each copy has
    /// an id of its own, so the writes name the rows of the new draft.
    private func writable(
        _ product: RemoteProduct,
        locales: [String],
        dryRun: Bool,
        progress: (@Sendable (String) -> Void)?,
        into result: inout TextResult
    ) async -> RemoteProduct? {
        guard product.version?.needsNewDraft == true else {
            return draft(of: product.version, for: product.productID,
                         locales: locales, into: &result) == nil ? nil : product
        }

        if dryRun {
            result.wouldSend.append(ProductWritePreview.newWordsVersion(
                of: product.isAutoRenewable ? .subscription : .inAppPurchase,
                parentID: product.id
            ))
            return product.with(
                version: Self.standInDraft,
                words: product.localizations.values.map {
                    RemoteProductLocalization(
                        id: Self.standInID(for: $0.locale), locale: $0.locale,
                        name: $0.name, description: $0.description
                    )
                }
            )
        }

        progress?(String(localized: "\(product.productID), new draft", bundle: .module))
        do {
            let made = try await client.newWordsDraft(for: product)
            return draft(of: made.version, for: product.productID,
                         locales: locales, into: &result) == nil ? nil : made
        } catch {
            result.failed.append(noNewDraft(product.productID, locales: locales, error: error))
            return nil
        }
    }

    /// The same for a subscription group.
    private func writable(
        _ group: RemoteSubscriptionGroup,
        locales: [String],
        dryRun: Bool,
        progress: (@Sendable (String) -> Void)?,
        into result: inout TextResult
    ) async -> RemoteSubscriptionGroup? {
        guard group.version?.needsNewDraft == true else {
            return draft(of: group.version, for: group.referenceName,
                         locales: locales, into: &result) == nil ? nil : group
        }

        if dryRun {
            result.wouldSend.append(ProductWritePreview.newWordsVersion(
                of: .subscriptionGroup, parentID: group.id
            ))
            return group.with(
                version: Self.standInDraft,
                words: group.localizations.values.map {
                    RemoteGroupLocalization(
                        id: Self.standInID(for: $0.locale), locale: $0.locale,
                        name: $0.name, customAppName: $0.customAppName
                    )
                }
            )
        }

        progress?(String(localized: "\(group.referenceName), new draft", bundle: .module))
        do {
            let made = try await client.newWordsDraft(for: group)
            return draft(of: made.version, for: group.referenceName,
                         locales: locales, into: &result) == nil ? nil : made
        } catch {
            result.failed.append(noNewDraft(group.referenceName, locales: locales, error: error))
            return nil
        }
    }

    private static let standInDraft = RemoteProductVersion(
        id: newDraftID, state: .prepareForSubmission
    )

    private static func standInID(for locale: String) -> String {
        "${new-draft-\(locale)}"
    }

    private func noNewDraft(_ productID: String, locales: [String], error: any Error) -> Failure {
        let refusal = ProductPushError.newDraftRefused(
            locales: locales, reason: ErrorMessage.text(for: error)
        )
        return Failure(
            productID: productID,
            what: "",
            reason: String(localized: refusal.localizedStringResource)
        )
    }

    /// The draft to write into, or nil with the refusal already recorded.
    ///
    /// Nil means none of this product's languages are attempted.
    private func draft(
        of version: RemoteProductVersion?,
        for productID: String,
        locales: [String],
        into result: inout TextResult
    ) -> RemoteProductVersion? {
        guard let version, version.acceptsChanges else {
            result.failed.append(noDraft(productID, locales: locales, version: version))
            return nil
        }
        // A dry run's stand-in is no version anybody can look for.
        if version.id != Self.newDraftID {
            result.drafts.append(
                Draft(productID: productID, versionID: version.id, number: version.number)
            )
        }
        return version
    }

    /// One failure for the whole product, naming the languages that did not go.
    ///
    /// Without the languages nobody can tell from the receipt what was skipped.
    /// `what` stays empty, which is what the field means when a whole product
    /// failed.
    private func noDraft(
        _ productID: String,
        locales: [String],
        version: RemoteProductVersion?
    ) -> Failure {
        let error: ProductPushError = if let state = version?.state?.rawValue {
            .versionIsClosed(
                locales: locales,
                state: state.lowercased().replacingOccurrences(of: "_", with: " ")
            )
        } else {
            .noDraft(locales: locales)
        }
        return Failure(
            productID: productID,
            what: "",
            reason: String(localized: error.localizedStringResource)
        )
    }

    /// The display name and the custom app name go out together, the way a
    /// product's two fields do.
    private func write(
        _ fields: [GroupField: String],
        locale: String,
        of group: RemoteSubscriptionGroup,
        in draft: RemoteProductVersion
    ) async throws {
        if let existing = group.localizations[locale] {
            _ = try await client.updateSubscriptionGroupLocalization(
                id: existing.id, name: fields[.name], customAppName: fields[.customAppName]
            )
            return
        }

        guard let name = fields[.name] else {
            throw ProductPushError.noNameToCreateWith(locale: locale)
        }

        _ = try await client.createSubscriptionGroupLocalization(
            versionID: draft.id,
            locale: locale,
            name: name,
            customAppName: fields[.customAppName]
        )
    }

    /// Throws wherever the write would throw, so a dry run never prints a body
    /// a real run would refuse to send.
    private func preview(
        _ fields: [GroupField: String],
        locale: String,
        of group: RemoteSubscriptionGroup,
        in draft: RemoteProductVersion
    ) throws -> String {
        if let existing = group.localizations[locale] {
            return ProductWritePreview.groupWordsChange(
                id: existing.id, name: fields[.name], customAppName: fields[.customAppName]
            )
        }
        guard let name = fields[.name] else {
            throw ProductPushError.noNameToCreateWith(locale: locale)
        }
        return ProductWritePreview.groupWords(
            versionID: draft.id,
            locale: locale,
            name: name,
            customAppName: fields[.customAppName]
        )
    }

    /// A name and a description go out together, because App Store Connect
    /// wants both on a create and there is no reason to make two calls.
    ///
    /// A language the draft already holds is written by changing that row. A
    /// language it does not hold is added to the draft, carrying both fields,
    /// because a new row needs the pair.
    ///
    /// Both questions are asked of the one draft. A row from any other version
    /// is a row App Review has already seen, and writing to one is refused.
    /// That is why a new draft comes back with its own rows.
    private func write(
        _ fields: [ProductField: String],
        locale: String,
        of product: RemoteProduct,
        in draft: RemoteProductVersion
    ) async throws {
        if let existing = product.localizations[locale] {
            if product.isAutoRenewable {
                _ = try await client.updateSubscriptionLocalization(
                    id: existing.id, name: fields[.name], description: fields[.description]
                )
            } else {
                _ = try await client.updateInAppPurchaseLocalization(
                    id: existing.id, name: fields[.name], description: fields[.description]
                )
            }
            return
        }

        // A new row needs a name. Nothing gets here without one, because both
        // fields are required in every language and the checker refuses a
        // product that publishes without them.
        guard let name = fields[.name] else {
            throw ProductPushError.noNameToCreateWith(locale: locale)
        }

        if product.isAutoRenewable {
            _ = try await client.createSubscriptionLocalization(
                versionID: draft.id, locale: locale,
                name: name, description: fields[.description]
            )
        } else {
            _ = try await client.createInAppPurchaseLocalization(
                versionID: draft.id, locale: locale,
                name: name, description: fields[.description]
            )
        }
    }

    /// Throws wherever the write would throw, so a dry run never prints a body
    /// a real run would refuse to send.
    private func preview(
        _ fields: [ProductField: String],
        locale: String,
        of product: RemoteProduct,
        in draft: RemoteProductVersion
    ) throws -> String {
        if let existing = product.localizations[locale] {
            return product.isAutoRenewable
                ? ProductWritePreview.subscriptionWordsChange(
                    id: existing.id, name: fields[.name], description: fields[.description]
                )
                : ProductWritePreview.purchaseWordsChange(
                    id: existing.id, name: fields[.name], description: fields[.description]
                )
        }
        guard let name = fields[.name] else {
            throw ProductPushError.noNameToCreateWith(locale: locale)
        }
        return product.isAutoRenewable
            ? ProductWritePreview.subscriptionWords(
                versionID: draft.id, locale: locale,
                name: name, description: fields[.description]
            )
            : ProductWritePreview.purchaseWords(
                versionID: draft.id, locale: locale,
                name: name, description: fields[.description]
            )
    }

    private func group(
        _ changes: [ChangePlan.GroupTextChange]
    ) -> [String: [String: [GroupField: String]]] {
        var grouped: [String: [String: [GroupField: String]]] = [:]
        for change in changes {
            grouped[change.group, default: [:]][change.locale, default: [:]][change.field] =
                change.newValue
        }
        return grouped
    }

    private func group(
        _ changes: [ChangePlan.ProductTextChange]
    ) -> [String: [String: [ProductField: String]]] {
        var grouped: [String: [String: [ProductField: String]]] = [:]
        for change in changes {
            grouped[change.productID, default: [:]][change.locale, default: [:]][change.field] =
                change.newValue
        }
        return grouped
    }
}
