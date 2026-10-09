import Foundation

// MARK: - Shapes

/// An image or a video in an app's library.
///
/// One type for both, because a list of placements brings images and videos
/// back mixed in one `included` array. Every field is optional for the same
/// reason: a field one of them has, the other lacks.
public struct LibraryAssetAttributes: Decodable, Sendable {
    public let category: LibraryAssetCategory?
    public let fileName: String?
    public let fileSize: Int?
    public let referenceName: String?
    public let specId: String?
    public let state: LibraryAssetState?
    public let stateDetails: [StateDetail]?
    public let uploadOperations: [UploadOperation]?
    public let imageAsset: ImageAsset?
    public let videoAsset: String?
    public let previewFrameTimeCode: String?
    public let previewFrameImage: PreviewFrameImage?
}

/// Apple's words about why an asset or a placement is where it is.
public struct StateDetail: Decodable, Sendable, Hashable {
    public let code: String?
    public let description: String?

    public init(code: String?, description: String?) {
        self.code = code
        self.description = description
    }

    var asErrorDetail: ASCErrorDetail {
        ASCErrorDetail(code: code, detail: description)
    }
}

/// The still frame App Store Connect shows for a video. It is made after the
/// video is processed, and again after each change to its time code.
public struct PreviewFrameImage: Decodable, Sendable {
    public let image: ImageAsset?
    public let state: String?
}

public struct PlacementAttributes: Decodable, Sendable {
    public let mediaType: LibraryMedia?
    public let placementType: PlacementType?
    public let placementGroup: String?
    public let state: PlacementState?
    public let stateDetails: [StateDetail]?
}

struct LibraryAssetReserveWrite: Encodable, Sendable {
    let category: String
    let fileName: String
    let fileSize: Int
    var referenceName: String?
    var previewFrameTimeCode: String?
}

/// Every field is optional, so a commit sends `uploaded` and nothing else.
/// There is no checksum in the library.
struct LibraryAssetUpdateWrite: Encodable, Sendable {
    var uploaded: Bool?
    var referenceName: String?
    var previewFrameTimeCode: String?
    var archived: Bool?
}

struct PlacementWrite: Encodable, Sendable {
    let placementType: String
    let placementGroup: String
}

struct OrderingWrite: Encodable, Sendable {
    let placementGroup: String
}

// MARK: - The library and its assets

public extension ASCClient {
    /// The id of an app's library. Apple makes one for each app and it never
    /// changes. Nil when App Store Connect has none for this app.
    func assetLibraryID(appID: String) async throws -> String? {
        do {
            return try await get("/v1/apps/\(appID)/assetLibrary", as: NoAttributes.self).id
        } catch ASCError.notFound {
            return nil
        }
    }

    /// Every image or every video in a library, with the ids of their
    /// placements. `ids` reads only those, in one call, which is how a push
    /// checks on many uploads at once.
    func libraryAssets(
        libraryID: String,
        media: LibraryMedia,
        ids: [String]? = nil
    ) async throws -> [Resource<LibraryAssetAttributes>] {
        var query = [
            URLQueryItem(name: "include", value: "placements"),
            .maxPageSize
        ]
        if let ids {
            guard ids.isEmpty == false else { return [] }
            query.append(URLQueryItem(name: "filter[id]", value: ids.joined(separator: ",")))
        }
        return try await list(
            "/v1/appAssetLibraries/\(libraryID)/\(media.listName)",
            query: query,
            as: LibraryAssetAttributes.self
        )
    }

    func libraryAsset(media: LibraryMedia, id: String) async throws -> Resource<LibraryAssetAttributes> {
        try await get("/v1/\(media.resourceType)/\(id)", as: LibraryAssetAttributes.self)
    }

    /// Step one of an upload: claim a place in the library and get told where
    /// to send the bytes. The category cannot change after this.
    func reserveLibraryAsset(
        media: LibraryMedia,
        libraryID: String,
        category: LibraryAssetCategory,
        fileName: String,
        fileSize: Int,
        referenceName: String? = nil,
        previewFrameTimeCode: String? = nil
    ) async throws -> Resource<LibraryAssetAttributes> {
        let body = WriteRequest<LibraryAssetReserveWrite>(
            data: .init(
                type: media.resourceType,
                id: nil,
                attributes: LibraryAssetReserveWrite(
                    category: category.rawValue,
                    fileName: fileName,
                    fileSize: fileSize,
                    referenceName: referenceName,
                    previewFrameTimeCode: media == .video ? previewFrameTimeCode : nil
                ),
                relationships: [
                    "assetLibrary": RelationshipToOne(type: "appAssetLibraries", id: libraryID)
                ]
            )
        )
        return try await post("/v1/\(media.resourceType)", body: body, as: LibraryAssetAttributes.self)
    }

    /// Step three: tell App Store Connect the bytes are all there. It checks
    /// them against the size given at reservation and refuses a mismatch.
    func commitLibraryAsset(media: LibraryMedia, id: String) async throws -> Resource<LibraryAssetAttributes> {
        try await updateLibraryAsset(media: media, id: id, LibraryAssetUpdateWrite(uploaded: true))
    }

    /// The poster frame of a video. It belongs to the video, so it changes on
    /// every placement of it.
    func setPreviewFrame(videoID: String, timeCode: String) async throws -> Resource<LibraryAssetAttributes> {
        try await updateLibraryAsset(
            media: .video, id: videoID, LibraryAssetUpdateWrite(previewFrameTimeCode: timeCode)
        )
    }

    func renameLibraryAsset(
        media: LibraryMedia,
        id: String,
        referenceName: String
    ) async throws -> Resource<LibraryAssetAttributes> {
        try await updateLibraryAsset(media: media, id: id, LibraryAssetUpdateWrite(referenceName: referenceName))
    }

    /// Only an approved asset can be archived. Anything else is refused with
    /// `LibraryRefusal.assetStateForbids`.
    func archiveLibraryAsset(
        media: LibraryMedia,
        id: String,
        archived: Bool = true
    ) async throws -> Resource<LibraryAssetAttributes> {
        try await updateLibraryAsset(media: media, id: id, LibraryAssetUpdateWrite(archived: archived))
    }

    /// Refused with `LibraryRefusal.assetHasPlacements` while a placement still
    /// uses the asset. Nothing cascades.
    func deleteLibraryAsset(media: LibraryMedia, id: String) async throws {
        try await delete("/v1/\(media.resourceType)/\(id)")
    }

    private func updateLibraryAsset(
        media: LibraryMedia,
        id: String,
        _ attributes: LibraryAssetUpdateWrite
    ) async throws -> Resource<LibraryAssetAttributes> {
        let body = WriteRequest<LibraryAssetUpdateWrite>(
            data: .init(type: media.resourceType, id: id, attributes: attributes, relationships: nil)
        )
        return try await patch("/v1/\(media.resourceType)/\(id)", body: body, as: LibraryAssetAttributes.self)
    }
}

// MARK: - Placements

public extension ASCClient {
    /// The placements on one localization, in the order the store shows them,
    /// with the assets they place.
    func placements(
        on parent: PlacementParent
    ) async throws -> (placements: [Resource<PlacementAttributes>], assets: [Resource<LibraryAssetAttributes>]) {
        let read = try await listMixed(
            "/v1/\(parent.resourceType)/\(parent.id)/placements",
            query: [
                URLQueryItem(name: "include", value: "image,video"),
                URLQueryItem(name: "sort", value: "placementGroupPosition"),
                .maxPageSize
            ],
            as: PlacementAttributes.self,
            including: LibraryAssetAttributes.self
        )
        return (read.data, read.included)
    }

    func createPlacement(
        type: PlacementType,
        group: String,
        media: LibraryMedia,
        assetID: String,
        on parent: PlacementParent
    ) async throws -> Resource<PlacementAttributes> {
        let body = WriteRequest<PlacementWrite>(
            data: .init(
                type: "appAssetLibraryPlacements",
                id: nil,
                attributes: PlacementWrite(placementType: type.rawValue, placementGroup: group),
                relationships: [
                    media.relationshipName: RelationshipToOne(type: media.resourceType, id: assetID),
                    parent.relationshipName: parent.relationship
                ]
            )
        )
        return try await post("/v1/appAssetLibraryPlacements", body: body, as: PlacementAttributes.self)
    }

    /// The asset and its other placements stay.
    func deletePlacement(id: String) async throws {
        try await delete("/v1/appAssetLibraryPlacements/\(id)")
    }

    /// Sets the order of one group on one localization. The list names every
    /// placement in the group, not only the ones that moved.
    func orderPlacements(group: String, on parent: PlacementParent, orderedIDs: [String]) async throws {
        let body = CompoundWriteRequest<OrderingWrite>(
            data: .init(
                type: "appAssetLibraryPlacementOrderingRequests",
                id: nil,
                attributes: OrderingWrite(placementGroup: group),
                relationships: [
                    "orderedPlacements": .many(orderedIDs.map {
                        Identifier(type: "appAssetLibraryPlacements", id: $0)
                    }),
                    parent.relationshipName: parent.relationship.asValue
                ]
            )
        )
        _ = try await post("/v1/appAssetLibraryPlacementOrderingRequests", compound: body, as: NoAttributes.self)
    }
}

// MARK: - Refusals

/// The refusals of the library that a push answers in its own way. App Store
/// Connect sends each as a 409 with a code of its own.
public enum LibraryRefusal: Sendable, Equatable {
    /// A delete of an asset that a placement still uses.
    case assetHasPlacements

    /// A change the asset's state does not allow, such as archiving one that
    /// is not approved.
    case assetStateForbids

    /// A placement on a parent that no longer takes changes, such as an
    /// approved version.
    case parentStateForbids

    /// A placement type, group and asset that do not go together.
    case placementNotSupported

    public init?(_ error: any Error) {
        guard let error = error as? ASCError else { return nil }
        let codes = error.details.compactMap(\.code)
        if codes.contains("STATE_ERROR.ASSET_HAS_PLACEMENTS") {
            self = .assetHasPlacements
        } else if codes.contains("STATE_ERROR.INVALID_ASSET_STATE") {
            self = .assetStateForbids
        } else if codes.contains("STATE_ERROR.INVALID_STATE") {
            self = .parentStateForbids
        } else if codes.contains("ENTITY_ERROR.ATTRIBUTE.INVALID") {
            self = .placementNotSupported
        } else {
            return nil
        }
    }
}
