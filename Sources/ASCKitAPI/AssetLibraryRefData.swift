import Foundation

/// What App Store Connect accepts in the library: the placement groups, the
/// exact sizes and formats, and how many of each a parent takes.
///
/// Apple says to read this rather than write the numbers down, because new
/// devices arrive as new strings. It is `Codable` so that a project can keep a
/// copy and check files without a network connection.
public struct AssetLibraryRefData: Codable, Sendable, Equatable {
    public var features: [Feature]
    public var placementProfileGroups: [ProfileGroup]
    public var imageSpecs: [ImageSpec]
    public var videoSpecs: [VideoSpec]
    public var placementTypes: [PlacementTypeEntry]
    public var displayClasses: [DisplayClassEntry]

    public init(
        features: [Feature] = [],
        placementProfileGroups: [ProfileGroup] = [],
        imageSpecs: [ImageSpec] = [],
        videoSpecs: [VideoSpec] = [],
        placementTypes: [PlacementTypeEntry] = [],
        displayClasses: [DisplayClassEntry] = []
    ) {
        self.features = features
        self.placementProfileGroups = placementProfileGroups
        self.imageSpecs = imageSpecs
        self.videoSpecs = videoSpecs
        self.placementTypes = placementTypes
        self.displayClasses = displayClasses
    }

    /// Apple leaves out any array it has nothing for, so each one decodes to
    /// empty when it is missing.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        features = try container.decodeIfPresent([Feature].self, forKey: .features) ?? []
        placementProfileGroups = try container.decodeIfPresent(
            [ProfileGroup].self, forKey: .placementProfileGroups
        ) ?? []
        imageSpecs = try container.decodeIfPresent([ImageSpec].self, forKey: .imageSpecs) ?? []
        videoSpecs = try container.decodeIfPresent([VideoSpec].self, forKey: .videoSpecs) ?? []
        placementTypes = try container.decodeIfPresent([PlacementTypeEntry].self, forKey: .placementTypes) ?? []
        displayClasses = try container.decodeIfPresent([DisplayClassEntry].self, forKey: .displayClasses) ?? []
    }

    // MARK: - The entries

    public struct Feature: Codable, Sendable, Equatable {
        public var featureId: String
        public var placementPolicies: [Policy]?

        public init(featureId: String, placementPolicies: [Policy]?) {
            self.featureId = featureId
            self.placementPolicies = placementPolicies
        }

        public struct Policy: Codable, Sendable, Equatable {
            public var placementType: PlacementType
            public var groupLimits: [GroupLimit]?

            public init(placementType: PlacementType, groupLimits: [GroupLimit]?) {
                self.placementType = placementType
                self.groupLimits = groupLimits
            }
        }

        public struct GroupLimit: Codable, Sendable, Equatable {
            public var groupIds: [String]?
            public var maxCount: Int?

            public init(groupIds: [String]?, maxCount: Int?) {
                self.groupIds = groupIds
                self.maxCount = maxCount
            }
        }
    }

    public struct ProfileGroup: Codable, Sendable, Equatable {
        public var placementProfileGroupId: String
        public var platform: String?
        public var displayClassId: String?

        public init(placementProfileGroupId: String, platform: String?, displayClassId: String?) {
            self.placementProfileGroupId = placementProfileGroupId
            self.platform = platform
            self.displayClassId = displayClassId
        }
    }

    public struct Dimensions: Codable, Sendable, Equatable {
        public var minWidth: Int
        public var maxWidth: Int
        public var minHeight: Int
        public var maxHeight: Int

        public init(minWidth: Int, maxWidth: Int, minHeight: Int, maxHeight: Int) {
            self.minWidth = minWidth
            self.maxWidth = maxWidth
            self.minHeight = minHeight
            self.maxHeight = maxHeight
        }

        /// Whether a picture of this size fits, either way up.
        public func fits(width: Int, height: Int) -> Bool {
            let upright = (minWidth ... maxWidth).contains(width) && (minHeight ... maxHeight).contains(height)
            let turned = (minWidth ... maxWidth).contains(height) && (minHeight ... maxHeight).contains(width)
            return upright || turned
        }
    }

    public struct ImageSpec: Codable, Sendable, Equatable {
        public var specId: String
        public var shortName: String?
        public var dimensions: Dimensions?
        public var aspectRatio: String?
        public var compatiblePlacementTypes: [PlacementType]?
        public var alphaAllowed: Bool?
        public var fileExtensions: [String]?
        public var maxFileSize: Int?
        public var mimeTypes: [String]?
        public var universalAsset: Bool?

        public init(
            specId: String,
            dimensions: Dimensions?,
            compatiblePlacementTypes: [PlacementType]? = nil,
            alphaAllowed: Bool? = nil,
            fileExtensions: [String]? = nil,
            maxFileSize: Int? = nil,
            universalAsset: Bool? = nil
        ) {
            self.specId = specId
            self.dimensions = dimensions
            self.compatiblePlacementTypes = compatiblePlacementTypes
            self.alphaAllowed = alphaAllowed
            self.fileExtensions = fileExtensions
            self.maxFileSize = maxFileSize
            self.universalAsset = universalAsset
        }
    }

    public struct VideoSpec: Codable, Sendable, Equatable {
        public var specId: String
        public var shortName: String?
        public var dimensions: Dimensions?
        public var aspectRatio: String?
        public var compatiblePlacementTypes: [PlacementType]?
        public var frameRates: [FrameRate]?
        public var duration: DurationRange?
        public var audioRequired: Bool?
        public var fileExtensions: [String]?
        public var maxFileSize: Int?
        public var mimeTypes: [String]?
        public var universalAsset: Bool?

        public struct FrameRate: Codable, Sendable, Equatable {
            public var minFps: Int
            public var maxFps: Int

            public init(minFps: Int, maxFps: Int) {
                self.minFps = minFps
                self.maxFps = maxFps
            }
        }

        /// ISO 8601 durations, such as `PT15S`.
        public struct DurationRange: Codable, Sendable, Equatable {
            public var min: String?
            public var max: String?

            public init(min: String?, max: String?) {
                self.min = min
                self.max = max
            }
        }

        public init(
            specId: String,
            dimensions: Dimensions?,
            compatiblePlacementTypes: [PlacementType]? = nil,
            frameRates: [FrameRate]? = nil,
            duration: DurationRange? = nil,
            audioRequired: Bool? = nil,
            fileExtensions: [String]? = nil,
            maxFileSize: Int? = nil,
            universalAsset: Bool? = nil
        ) {
            self.specId = specId
            self.dimensions = dimensions
            self.compatiblePlacementTypes = compatiblePlacementTypes
            self.frameRates = frameRates
            self.duration = duration
            self.audioRequired = audioRequired
            self.fileExtensions = fileExtensions
            self.maxFileSize = maxFileSize
            self.universalAsset = universalAsset
        }
    }

    public struct PlacementTypeEntry: Codable, Sendable, Equatable {
        public var placementTypeId: PlacementType
        public var acceptsAssetCategories: [LibraryAssetCategory]?
        public var specMappings: [SpecMapping]?

        public init(
            placementTypeId: PlacementType,
            acceptsAssetCategories: [LibraryAssetCategory]?,
            specMappings: [SpecMapping]?
        ) {
            self.placementTypeId = placementTypeId
            self.acceptsAssetCategories = acceptsAssetCategories
            self.specMappings = specMappings
        }

        public struct SpecMapping: Codable, Sendable, Equatable {
            public var placementGroupId: String
            public var specs: [String]

            public init(placementGroupId: String, specs: [String]) {
                self.placementGroupId = placementGroupId
                self.specs = specs
            }
        }
    }

    public struct DisplayClassEntry: Codable, Sendable, Equatable {
        public var displayClassId: String
        public var deviceFamily: String?
        public var screenDimensions: [String]?
    }
}

// MARK: - Looking things up

public extension AssetLibraryRefData {
    /// The most of one placement type a group holds on one feature, such as
    /// 10 screenshots for a version. Nil when Apple names no limit.
    func maximumCount(feature: String, type: PlacementType, group: String) -> Int? {
        let policy = features.first { $0.featureId == feature }?
            .placementPolicies?.first { $0.placementType == type }
        return policy?.groupLimits?.first { $0.groupIds?.contains(group) == true }?.maxCount
    }

    /// The ids of the specs a file has to match to go in this group.
    func specIDs(type: PlacementType, group: String) -> [String] {
        placementTypes.first { $0.placementTypeId == type }?
            .specMappings?.first { $0.placementGroupId == group }?.specs ?? []
    }

    func imageSpecs(type: PlacementType, group: String) -> [ImageSpec] {
        let wanted = Set(specIDs(type: type, group: group))
        return imageSpecs.filter { wanted.contains($0.specId) }
    }

    func videoSpecs(type: PlacementType, group: String) -> [VideoSpec] {
        let wanted = Set(specIDs(type: type, group: group))
        return videoSpecs.filter { wanted.contains($0.specId) }
    }

    func profileGroup(_ id: String) -> ProfileGroup? {
        placementProfileGroups.first { $0.placementProfileGroupId == id }
    }

    /// The category an asset needs to go in a placement of this type.
    func category(for type: PlacementType) -> LibraryAssetCategory? {
        placementTypes.first { $0.placementTypeId == type }?.acceptsAssetCategories?.first
    }
}

public extension ASCClient {
    /// Read once at the start of a push and kept. It is the same for every app.
    func assetLibraryRefData() async throws -> AssetLibraryRefData {
        let resources = try await list("/v1/appAssetLibraryRefData", as: AssetLibraryRefData.self)
        return resources.first?.attributes ?? AssetLibraryRefData()
    }
}
