import ASCKitAPI
import CryptoKit
import Foundation

public extension ChangePlan {
    /// A digest of everything this plan would do, at full length.
    ///
    /// This is how a caller tells that the plan somebody read a minute ago is
    /// still the plan. App Store Connect changes without asking, so an upload
    /// reads it again first, and writing what came back the second time would
    /// be writing something nobody agreed to.
    ///
    /// Values go in whole, not shortened the way they are shortened on screen,
    /// so a change past the end of a printed line still moves the digest.
    var digest: String {
        digest(includingPricePointIDs: true)
    }

    /// The same, without Apple's identifier for each price point.
    ///
    /// This is what a person agreed to: the money, and where each number came
    /// from. The identifier is Apple's own bookkeeping, and it is left out on
    /// purpose.
    ///
    /// Leaving it in refuses pushes it cannot protect. A push writes the plan
    /// from the *second* read, not the one on screen, so an identifier Apple
    /// regenerated between the two goes out correctly either way. Comparing
    /// them can only stop a push whose every price is the same.
    ///
    /// `digest` keeps the identifiers, because a record of what a plan held is
    /// a different thing from what somebody said yes to.
    var agreementDigest: String {
        digest(includingPricePointIDs: false)
    }

    private func digest(includingPricePointIDs: Bool) -> String {
        var hasher = SHA256()
        func feed(_ parts: String...) {
            for part in parts {
                hasher.update(data: Data(part.utf8))
                hasher.update(data: Data([0]))
            }
        }

        feed(versionString, versionState?.rawValue ?? "")
        feed(missingLocales.joined(separator: ","))

        for change in textChanges {
            feed(
                change.locale, change.field.rawValue, change.action.rawValue,
                change.oldValue ?? "", change.newValue
            )
        }

        // The bytes of an image are not read here. A set that gained, lost or
        // moved a file changes its action, and a file edited in place changes
        // its size, so the plan moves either way.
        for plan in screenshotPlans {
            feed(plan.locale, plan.deviceClass.id, plan.action.digestKey, "\(plan.remoteCount)")
            for file in plan.localFiles {
                feed(file.fileName, "\(file.byteCount)")
            }
        }

        // Fed only when there is one, so a plan with no previews keeps the
        // digest it had before previews.
        for plan in previewPlans {
            feed(plan.id, plan.action.digestKey, "\(plan.remoteCount)")
            for file in plan.localFiles {
                feed(file.fileName, "\(file.byteCount)", file.posterFrame ?? "")
            }
        }
        for plan in creativePlans {
            feed(plan.id, plan.action.digestKey, plan.file?.fileName ?? "", "\(plan.file?.byteCount ?? 0)")
        }

        // Fed only when there is one, so a plan with none keeps its digest.
        for file in unusedFiles {
            feed("unused", file.locale, file.slotID, file.fileName)
        }

        for change in productTextChanges {
            feed(
                change.productID, change.locale, change.field.rawValue,
                change.action.rawValue, change.oldValue ?? "", change.newValue
            )
        }

        // Fed only when there is one, so a plan with no group words keeps the
        // digest it had before groups had words.
        for change in groupTextChanges {
            feed(
                "group", change.group, change.locale, change.field.rawValue,
                change.action.rawValue, change.oldValue ?? "", change.newValue
            )
        }

        // Fed only when there is one, so older plans keep their digest.
        for change in retentionTextChanges {
            feed(
                "retention", change.message, change.locale, change.field.rawValue,
                change.action.rawValue, change.oldValue ?? "", change.newValue
            )
        }
        for image in retentionImages {
            feed("retention-image", image.message, image.md5)
        }

        // Every country goes in, not only the ones that change. A one-time
        // purchase's write sends all of them, so all of them are what somebody
        // agreed to. Where the number came from goes in too, so that a row
        // moving from the curve to an override with the same amount still
        // counts as a change.
        //
        // The price point id goes in only for `digest`. See `agreementDigest`
        // for why the check a push makes leaves it out.
        feed(newProducts.joined(separator: ","))
        for plan in pricePlans {
            feed(
                plan.productID, plan.kind.rawValue, plan.curveID,
                plan.baseTerritory, plan.baseAmount.description,
                plan.replacesWholeSchedule ? "replace" : "merge",
                plan.preserveCurrentPrice.map { $0 ? "preserve" : "raise" } ?? ""
            )
            for row in plan.rows {
                feed(
                    row.territory, row.planType.rawValue,
                    row.currency ?? "",
                    includingPricePointIDs ? row.pricePointID : "",
                    row.oldAmount?.description ?? "", row.newAmount.description,
                    row.direction.rawValue, row.source.digestKey
                )
            }
            for left in plan.skipped {
                feed(left.territory, left.reason.english)
            }
        }

        // The English, not the reader's own words. A digest is compared with
        // one written earlier, and a change of language must not look like a
        // change of plan.
        for item in blocked {
            feed(item.reason.english, item.affects.english)
        }
        for item in skipped {
            feed(item.locale, item.reason.english)
        }

        let hex = hasher.finalize().hexString
        return "sha256:\(hex)"
    }
}

private extension ChangePlan.ScreenshotPlan.Action {
    /// Written out rather than interpolated, so the digest does not depend on
    /// how Swift happens to describe an enum with values in it.
    var digestKey: String {
        switch self {
        case .unchanged: "unchanged"
        case let .replace(removing, adding): "replace-\(removing)-\(adding)"
        }
    }
}
