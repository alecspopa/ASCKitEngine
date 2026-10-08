import Foundation

/// App Store Connect wraps everything in JSON:API, so every payload has the
/// same shape: a `data` member holding a type, an id and an attributes bag.
public struct Resource<Attributes: Decodable & Sendable>: Decodable, Sendable {
    public let type: String
    public let id: String
    public let attributes: Attributes?

    /// What this resource points at, by id.
    ///
    /// Optional, so every payload that decoded before still decodes. It is here
    /// because a price point names its territory only in its relationships, and
    /// reading it there saves parsing the top-level `included` array on every
    /// list of thousands.
    public let relationships: [String: RelationshipData]?

    /// The id of a to-one relationship, such as the territory a price point is
    /// in. Nil when the relationship is missing or points at many.
    public func related(_ name: String) -> String? {
        guard case let .one(identifier)? = relationships?[name]?.data else { return nil }
        return identifier?.id
    }
}

/// A relationship as it comes back: one identifier, or many, or nothing.
public struct RelationshipData: Decodable, Sendable {
    public let data: Payload?

    public enum Payload: Decodable, Sendable {
        case one(Identifier?)
        case many([Identifier])

        public init(from decoder: any Decoder) throws {
            let container = try decoder.singleValueContainer()
            if container.decodeNil() {
                self = .one(nil)
            } else if let many = try? container.decode([Identifier].self) {
                self = .many(many)
            } else {
                self = try .one(container.decode(Identifier.self))
            }
        }
    }
}

struct SingleResponse<Attributes: Decodable & Sendable>: Decodable, Sendable {
    let data: Resource<Attributes>
}

struct ListResponse<Attributes: Decodable & Sendable>: Decodable, Sendable {
    let data: [Resource<Attributes>]

    /// Resources asked for with `include`.
    ///
    /// Almost nothing needs these: a relationship's id is on the resource
    /// itself, which is enough to match things up. What does need them is a
    /// price, whose amount lives on the price point it points at rather than on
    /// the price.
    let included: [Resource<Attributes>]?

    let links: Links?
    let meta: Meta?

    struct Links: Decodable, Sendable {
        let next: String?
    }

    struct Meta: Decodable, Sendable {
        let paging: Paging?

        struct Paging: Decodable, Sendable {
            let total: Int?
            let limit: Int?
        }
    }
}

/// A list whose `included` resources are of another kind than its data, such
/// as placements that bring their images and videos along.
struct MixedListResponse<Attributes: Decodable & Sendable, Included: Decodable & Sendable>: Decodable, Sendable {
    let data: [Resource<Attributes>]
    let included: [Resource<Included>]?
    let links: ListResponse<Attributes>.Links?
}

/// The body shape for a create or an update.
struct WriteRequest<Attributes: Encodable & Sendable>: Encodable, Sendable {
    let data: Payload

    struct Payload: Encodable, Sendable {
        let type: String
        var id: String?
        var attributes: Attributes?
        var relationships: [String: RelationshipToOne]?
    }
}

struct RelationshipToOne: Encodable, Sendable {
    let data: Identifier

    init(type: String, id: String) {
        data = Identifier(type: type, id: id)
    }

    var asValue: RelationshipValue { .one(data) }
}

/// A relationship that points at one thing or at many.
///
/// `WriteRequest` takes only the first kind, which covers every write ASCKit
/// made before in-app purchases. A price schedule needs the second.
enum RelationshipValue: Encodable, Sendable {
    case one(Identifier)
    case many([Identifier])

    private enum CodingKeys: String, CodingKey { case data }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .one(identifier): try container.encode(identifier, forKey: .data)
        case let .many(identifiers): try container.encode(identifiers, forKey: .data)
        }
    }
}

/// A write whose body carries resources that do not exist yet.
///
/// This is the only way to make an in-app purchase price schedule. The prices
/// have to be created in the same request as the schedule that points at them,
/// so each one travels in `included` under a local id, and `manualPrices`
/// points at those ids. A local id is unique within the one request and is
/// never a real resource id: nothing comes back holding it.
///
/// Kept apart from `WriteRequest` rather than folded into it. Every existing
/// write builds its relationships as a dictionary literal of
/// `RelationshipToOne`, and the tests assert on the exact JSON those produce.
struct CompoundWriteRequest<Attributes: Encodable & Sendable>: Encodable, Sendable {
    let data: Payload
    var included: [IncludedResource]?

    struct Payload: Encodable, Sendable {
        let type: String
        var id: String?
        var attributes: Attributes?
        var relationships: [String: RelationshipValue]?
    }
}

/// One of the resources created alongside the main one.
struct IncludedResource: Encodable, Sendable {
    let type: String

    /// A local id, such as `${price-USA}`. Unique in this request only.
    let id: String

    var attributes: [String: JSONValue]?
    var relationships: [String: RelationshipValue]?
}

/// A value in an included resource's attributes.
///
/// Included resources are heterogeneous by nature, so they cannot share one
/// `Attributes` type the way the main payload does. `.null` matters: on a price
/// it is what says "from now" rather than "no start date given".
enum JSONValue: Encodable, Sendable {
    case string(String)
    case int(Int)
    case bool(Bool)
    case null

    func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value): try container.encode(value)
        case let .int(value): try container.encode(value)
        case let .bool(value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

struct RelationshipToMany: Encodable, Sendable {
    let data: [Identifier]
}

public struct Identifier: Codable, Sendable, Hashable {
    public let type: String
    public let id: String

    public init(type: String, id: String) {
        self.type = type
        self.id = id
    }
}

/// A body with no attributes, for creates that carry only relationships.
struct NoAttributes: Codable, Sendable {}
