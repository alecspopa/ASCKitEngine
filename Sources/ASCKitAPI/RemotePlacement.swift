import Foundation

/// One asset of the library placed on one localization, as App Store Connect
/// holds it.
public struct RemotePlacement: Sendable, Equatable {
    public let id: String
    public let locale: String
    public let type: PlacementType?
    public let group: String?
    public let state: PlacementState?
    public let asset: RemoteLibraryAsset?

    public init(
        id: String,
        locale: String,
        type: PlacementType?,
        group: String?,
        state: PlacementState?,
        asset: RemoteLibraryAsset?
    ) {
        self.id = id
        self.locale = locale
        self.type = type
        self.group = group
        self.state = state
        self.asset = asset
    }
}

/// An image or a video in the library.
///
/// It has no checksum. What says that a local file is this asset is the
/// record a project keeps of what it uploaded.
public struct RemoteLibraryAsset: Sendable, Equatable {
    public let id: String
    public let media: LibraryMedia
    public let category: LibraryAssetCategory?
    public let fileName: String?
    public let fileSize: Int?
    public let referenceName: String?
    public let specID: String?
    public let state: LibraryAssetState?
    public let stateDetails: [StateDetail]
    public let previewFrameTimeCode: String?

    /// What the store shows for it: the image, or the poster frame of a video.
    /// Something to look at, never something to write into a project.
    public let preview: RemoteImage?

    public init(
        id: String,
        media: LibraryMedia,
        category: LibraryAssetCategory? = nil,
        fileName: String? = nil,
        fileSize: Int? = nil,
        referenceName: String? = nil,
        specID: String? = nil,
        state: LibraryAssetState? = nil,
        stateDetails: [StateDetail] = [],
        previewFrameTimeCode: String? = nil,
        preview: RemoteImage? = nil
    ) {
        self.id = id
        self.media = media
        self.category = category
        self.fileName = fileName
        self.fileSize = fileSize
        self.referenceName = referenceName
        self.specID = specID
        self.state = state
        self.stateDetails = stateDetails
        self.previewFrameTimeCode = previewFrameTimeCode
        self.preview = preview
    }

    /// Nil for a resource that is neither an image nor a video.
    public init?(_ resource: Resource<LibraryAssetAttributes>) {
        guard let media = LibraryMedia(resourceType: resource.type) else { return nil }
        let attributes = resource.attributes
        self.init(
            id: resource.id,
            media: media,
            category: attributes?.category,
            fileName: attributes?.fileName,
            fileSize: attributes?.fileSize,
            referenceName: attributes?.referenceName,
            specID: attributes?.specId,
            state: attributes?.state,
            stateDetails: attributes?.stateDetails ?? [],
            previewFrameTimeCode: attributes?.previewFrameTimeCode,
            preview: ASCClient.preview(of: attributes?.imageAsset ?? attributes?.previewFrameImage?.image)
        )
    }
}

/// An app's library and everything in it.
public struct RemoteAssetLibrary: Sendable {
    public let id: String
    public let assets: [RemoteLibraryAsset]

    /// The placement ids of each asset. An asset with none can be deleted.
    public let placementIDs: [String: [String]]

    public init(id: String, assets: [RemoteLibraryAsset], placementIDs: [String: [String]]) {
        self.id = id
        self.assets = assets
        self.placementIDs = placementIDs
    }
}

public extension ASCClient {
    /// The placements on one localization, in the order the store shows them.
    func readPlacements(on parent: PlacementParent, locale: String) async throws -> [RemotePlacement] {
        let read = try await placements(on: parent)
        let assets = Dictionary(
            read.assets.compactMap { RemoteLibraryAsset($0) }.map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        return read.placements.map { placement in
            let attributes = placement.attributes
            let assetID = placement.related("image") ?? placement.related("video")
            return RemotePlacement(
                id: placement.id,
                locale: locale,
                type: attributes?.placementType,
                group: attributes?.placementGroup,
                state: attributes?.state,
                asset: assetID.flatMap { assets[$0] }
            )
        }
    }

    /// The placements of many localizations, read together.
    func readPlacements(_ parents: [(parent: PlacementParent, locale: String)]) async throws -> [RemotePlacement] {
        let outcomes = await withTaskGroup(of: Result<[RemotePlacement], any Error>.self) { group in
            for (parent, locale) in parents {
                group.addTask {
                    await Self.captured { try await readPlacements(on: parent, locale: locale) }
                }
            }
            var collected: [Result<[RemotePlacement], any Error>] = []
            for await outcome in group {
                collected.append(outcome)
            }
            return collected
        }

        // By locale only. Within a locale the order is the store's, and that
        // order is what a plan compares with.
        let all = try Self.unwrap(outcomes)
        return all.sorted { ($0.first?.locale ?? "") < ($1.first?.locale ?? "") }.flatMap(\.self)
    }

    /// Everything in an app's library. Nil when the app has no library.
    func readAssetLibrary(appID: String) async throws -> RemoteAssetLibrary? {
        guard let libraryID = try await assetLibraryID(appID: appID) else { return nil }

        async let images = libraryAssets(libraryID: libraryID, media: .image)
        let videos = try await libraryAssets(libraryID: libraryID, media: .video)
        let all = try await images + videos

        var placementIDs: [String: [String]] = [:]
        for resource in all {
            if case let .many(identifiers)? = resource.relationships?["placements"]?.data {
                placementIDs[resource.id] = identifiers.map(\.id)
            }
        }
        return RemoteAssetLibrary(
            id: libraryID,
            assets: all.compactMap { RemoteLibraryAsset($0) },
            placementIDs: placementIDs
        )
    }
}
