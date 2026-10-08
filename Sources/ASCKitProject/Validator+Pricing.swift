import Foundation

/// What is wrong with a price plan, as far as anybody can tell with no network.
///
/// The prices themselves cannot be checked here. A price point belongs to one
/// product in one country, and only App Store Connect knows the ladder. What
/// this checks is everything that is wrong before a single request goes out: a
/// curve nobody has heard of, a country that does not exist, an amount that is
/// not a number.
extension Validator {
    func validatePricing(_ catalog: ProductCatalog) -> [Problem] {
        var problems = validateDefaults()
        for product in catalog.sorted {
            problems += validatePricing(of: product)
        }
        return problems
    }

    // MARK: - What the project starts a new product with

    private func validateDefaults() -> [Problem] {
        var problems: [Problem] = []

        if Territory.isKnown(config.baseTerritory) == false {
            problems.append(Problem(
                severity: .error,
                area: .configuration,
                message: LocalizedStringResource("\(config.baseTerritory) is not a country the App Store sells in.", bundle: .here),
                fix: suggestion(forTerritory: config.baseTerritory),
                territory: config.baseTerritory,
                path: Project.defaultConfigName,
                kind: .baseTerritoryNotKnown
            ))
        }

        if PriceCurve.isKnown(config.defaultPriceCurve) == false {
            problems.append(Problem(
                severity: .error,
                area: .configuration,
                message: LocalizedStringResource("\(config.defaultPriceCurve) is not a price curve ASCKit knows.", bundle: .here),
                fix: LocalizedStringResource("Use one of: \(PriceCurve.allIdentifiers.joined(separator: ", ")).", bundle: .here),
                path: Project.defaultConfigName,
                kind: .defaultCurveNotKnown
            ))
        }

        return problems
    }

    // MARK: - One product's plan

    private func validatePricing(of product: Product) -> [Problem] {
        guard let plan = product.price else { return [] }

        var problems: [Problem] = []
        let filePath = path(for: product.productID)

        if plan.baseAmount.isPositive == false {
            problems.append(Problem(
                severity: .error,
                area: .pricing,
                message: LocalizedStringResource(
                    "\(product.productID) has a base price of \(plan.baseAmount.description).", bundle: .here
                ),
                fix: LocalizedStringResource("Write a price above zero. A free product has no price plan at all.", bundle: .here),
                productID: product.productID,
                path: filePath,
                kind: .baseAmountNotANumber
            ))
        }

        if Territory.isKnown(plan.baseTerritory) == false {
            problems.append(Problem(
                severity: .error,
                area: .pricing,
                message: LocalizedStringResource("""
                \(product.productID) is priced from \(plan.baseTerritory), which is \
                not a country the App Store sells in.
                """, bundle: .here),
                fix: suggestion(forTerritory: plan.baseTerritory),
                productID: product.productID,
                territory: plan.baseTerritory,
                path: filePath,
                kind: .productBaseTerritoryNotKnown
            ))
        }

        guard let curve = PriceCurve.named(plan.curve) else {
            problems.append(Problem(
                severity: .error,
                area: .pricing,
                message: LocalizedStringResource("\(product.productID) asks for a price curve called \(plan.curve).", bundle: .here),
                fix: LocalizedStringResource("""
                Use one of: \(PriceCurve.allIdentifiers.joined(separator: ", ")). \
                A company name such as netflix finds one too.
                """, bundle: .here),
                productID: product.productID,
                path: filePath,
                kind: .productCurveNotKnown
            ))
            return problems
        }

        problems += validateProvenance(of: curve, product: product, path: filePath)
        problems += validateOverrides(in: plan, product: product, path: filePath)
        problems += validateStartDate(plan.startDate, product: product, path: filePath)

        return problems
    }

    // MARK: - Overrides

    private func validateOverrides(
        in plan: Product.PricePlan,
        product: Product,
        path: String
    ) -> [Problem] {
        var problems: [Problem] = []

        for territory in plan.overrides.keys.sorted() {
            guard let override = plan.overrides[territory] else { continue }

            if Territory.isKnown(territory) == false {
                problems.append(Problem(
                    severity: .error,
                    area: .pricing,
                    message: LocalizedStringResource("""
                    \(product.productID) sets a price for \(territory), which is not \
                    a country the App Store sells in.
                    """, bundle: .here),
                    fix: suggestion(forTerritory: territory),
                    productID: product.productID,
                    territory: territory,
                    path: path,
                    kind: .overrideTerritoryNotKnown
                ))
            }

            if override.amount != nil, override.pricePoint != nil {
                problems.append(Problem(
                    severity: .error,
                    area: .pricing,
                    message: LocalizedStringResource("The price for \(territory) names both an amount and a price point.", bundle: .here),
                    fix: LocalizedStringResource("""
                    Keep one. An amount is rounded up to a real point, and a point is \
                    taken as it is.
                    """, bundle: .here),
                    productID: product.productID,
                    territory: territory,
                    path: path,
                    kind: .overrideSaysBoth
                ))
            }

            if override.isEmpty {
                problems.append(Problem(
                    severity: .warning,
                    area: .pricing,
                    message: LocalizedStringResource("The override for \(territory) says nothing about what to charge.", bundle: .here),
                    fix: LocalizedStringResource("""
                    Give it an amount, a price point, or skip. Otherwise take it out and \
                    let the curve decide.
                    """, bundle: .here),
                    productID: product.productID,
                    territory: territory,
                    path: path,
                    kind: .overrideSaysNothing
                ))
            }

            if let amount = override.amount, amount.isPositive == false {
                problems.append(Problem(
                    severity: .error,
                    area: .pricing,
                    message: LocalizedStringResource("The price for \(territory) is \(amount.description).", bundle: .here),
                    fix: LocalizedStringResource("Write a price above zero, or skip the country.", bundle: .here),
                    productID: product.productID,
                    territory: territory,
                    path: path,
                    kind: .overrideAmountNotANumber
                ))
            }

            // The unexplained-override warning belongs to the resolver, which
            // reports it with the rest of the resolution. Repeating it here
            // would show it twice in one check.
        }

        return problems
    }

    // MARK: - Dates and staleness

    private func validateStartDate(
        _ written: String?,
        product: Product,
        path: String
    ) -> [Problem] {
        guard let written else { return [] }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        guard formatter.date(from: written) == nil else { return [] }

        return [Problem(
            severity: .error,
            area: .pricing,
            message: LocalizedStringResource("\(written) is not a date this price can start on.", bundle: .here),
            fix: LocalizedStringResource("Write it as 2026-09-01, or leave it out to start as soon as the write lands.", bundle: .here),
            productID: product.productID,
            path: path,
            kind: .startDateNotADate
        )]
    }

    /// A curve's numbers are a snapshot of the world. Income groups move, and
    /// tax rates move more often. A table nobody has looked at in a year is
    /// worth saying out loud once.
    private func validateProvenance(
        of curve: PriceCurve,
        product: Product,
        path: String
    ) -> [Problem] {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        guard let taken = formatter.date(from: curve.provenance.takenOn) else { return [] }

        let year: TimeInterval = 365 * 24 * 60 * 60
        guard Date().timeIntervalSince(taken) > year else { return [] }

        return [Problem(
            severity: .warning,
            area: .pricing,
            message: LocalizedStringResource("""
            The \(curve.id) numbers were taken on \(curve.provenance.takenOn), which \
            is over a year ago.
            """, bundle: .here),
            fix: LocalizedStringResource("Read the resolved prices before pushing. \(curve.provenance.source)", bundle: .here),
            productID: product.productID,
            path: path,
            kind: .curveProceedsDrift
        )]
    }

    private func suggestion(forTerritory territory: String) -> LocalizedStringResource {
        if let meant = Territory.suggestion(for: territory) {
            return LocalizedStringResource(
                "Use \(meant) instead. App Store Connect uses the three-letter code.", bundle: .here
            )
        }
        return LocalizedStringResource(
            "App Store Connect uses the three-letter code, USA and DEU, not the two-letter one.", bundle: .here
        )
    }
}
