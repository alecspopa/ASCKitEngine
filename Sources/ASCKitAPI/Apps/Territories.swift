import Foundation

/// A country or region the App Store sells in.
///
/// The resource id is the ISO-3166 alpha-3 code, `USA` and `DEU`, and the
/// currency is the only attribute. That currency is the one App Store Connect
/// bills in, which is not always the country's own, so it is read here rather
/// than worked out from the country.
struct TerritoryAttributes: Decodable, Sendable {
    let currency: String?
}

public extension ASCClient {
    /// The currency of every territory, about 175 of them, keyed by the
    /// territory's code. Nil for a territory App Store Connect names no
    /// currency for.
    ///
    /// One page. The limit is asked for anyway, because the default is 50 and
    /// three round trips for a list that never changes is three too many.
    func territoryCurrencies() async throws -> [String: String?] {
        let territories = try await list("/v1/territories", query: [.maxPageSize], as: TerritoryAttributes.self)
        return Dictionary(territories.map { ($0.id, $0.attributes?.currency) }, uniquingKeysWith: { first, _ in first })
    }
}
