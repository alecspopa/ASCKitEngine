import ASCKitAPI
import Foundation

/// Puts the image of each retention message on its version.
///
/// The file goes into the app's library once, by its checksum, and the record
/// keeps it. Then the old placement goes and a new one takes its place. A
/// version holds one image for every language.
extension PushSession {
    func pushRetentionImages(
        _ plan: ChangePlan,
        to remote: RemoteProducts,
        dryRun: Bool,
        progress: (@Sendable (String) -> Void)?,
        into result: inout ProductPusher.TextResult
    ) async {
        guard plan.retentionImages.isEmpty == false else { return }
        let byName = remote.retentionMessagesByName

        if dryRun {
            for change in plan.retentionImages {
                let source = change.uploadedAssetID.map { "asset \($0)" } ?? "upload \(change.fileName)"
                result.wouldSend.append("\(change.message): \(source), placed on the message version")
            }
            return
        }

        let libraryID: String
        let refData: AssetLibraryRefData?
        do {
            guard let found = try await client.assetLibraryID(appID: remote.appID) else {
                throw LibraryReadError.noLibrary
            }
            libraryID = found
            refData = try? await client.assetLibraryRefData()
        } catch {
            for change in plan.retentionImages {
                result.failed.append(.init(productID: change.message, what: change.fileName,
                                           reason: ErrorMessage.text(for: error)))
            }
            return
        }

        for change in plan.retentionImages {
            progress?("\(change.message), \(change.fileName)")
            guard let version = byName[change.message]?.version, version.acceptsChanges else {
                result.failed.append(.init(
                    productID: change.message, what: change.fileName,
                    reason: String(localized: "App Store Connect no longer takes changes to this retention message.",
                                   bundle: .module)
                ))
                continue
            }
            do {
                let assetID = try await retentionAsset(for: change, libraryID: libraryID, refData: refData)
                if let old = version.placementID {
                    try await client.deletePlacement(id: old)
                }
                let group = refData?.placementTypes.first { $0.placementTypeId == .retentionMessage }?
                    .specMappings?.first?.placementGroupId
                _ = try await client.createPlacement(
                    type: .retentionMessage, group: group, media: .image, assetID: assetID,
                    on: .retentionMessageVersion(id: version.id)
                )
                result.written.append("\(change.message) \(change.fileName)")
            } catch {
                result.failed.append(.init(productID: change.message, what: change.fileName,
                                           reason: ErrorMessage.text(for: error)))
            }
        }
    }

    /// The asset the record holds for these bytes, or a new upload that the
    /// record keeps from now on.
    private func retentionAsset(
        for change: ChangePlan.RetentionImageChange,
        libraryID: String,
        refData: AssetLibraryRefData?
    ) async throws -> String {
        if let known = change.uploadedAssetID { return known }

        let category = refData?.category(for: .retentionMessage) ?? .creativeAssets
        let uploader = LibraryUploader(client: client)
        let committed = try await uploader.upload(
            .init(fileURL: change.fileURL, media: .image, category: category), libraryID: libraryID
        )
        let processed = try await uploader.waitUntilProcessed([.image: [committed.assetID]], libraryID: libraryID)
        if let asset = processed[committed.assetID], asset.state == .failed {
            throw asset.failure(fileName: change.fileName)
        }

        var record = (try? AssetRecordStore.load(in: project)) ?? AssetRecord()
        record.record(md5: change.md5, .init(
            assetID: committed.assetID, media: .image, category: category,
            fileName: change.fileName, fileSize: change.fileSize, uploadedAt: .now
        ))
        try AssetRecordStore.save(record, in: project)
        return committed.assetID
    }
}
