import Foundation

/// A country or region the App Store sells in.
///
/// The resource id is the ISO-3166 alpha-3 code, `USA` and `DEU`, and the
/// currency is the only attribute. That currency is the one App Store Connect
/// bills in, which is not always the country's own, so it is read here rather
/// than worked out from the country.
public struct TerritoryAttributes: Decodable, Sendable {
    public let currency: String?
}

public extension ASCClient {
    /// Every territory, about 175 of them.
    ///
    /// One page. The limit is asked for anyway, because the default is 50 and
    /// three round trips for a list that never changes is three too many.
    func territories() async throws -> [Resource<TerritoryAttributes>] {
        try await list(
            "/v1/territories",
            query: [URLQueryItem(name: "limit", value: "200")],
            as: TerritoryAttributes.self
        )
    }
}
