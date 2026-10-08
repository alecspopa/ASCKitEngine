import Foundation

/// Where `Territory.all` and `/v1/territories` have stopped agreeing.
///
/// App Store Connect is the authority. The table exists so a check and a price
/// line work with no network, and this is how a person finds out it is old.
public enum TerritoryDrift {
    public struct CurrencyChange: Sendable, Equatable {
        public let territory: String
        public let table: String
        public let appStoreConnect: String?

        public init(territory: String, table: String, appStoreConnect: String?) {
            self.territory = territory
            self.table = table
            self.appStoreConnect = appStoreConnect
        }
    }

    public struct Outcome: Sendable, Equatable {
        /// Territories App Store Connect sells in that the table leaves out.
        public let missingHere: [String]

        /// Territories the table lists that App Store Connect did not return.
        public let missingThere: [String]

        /// Territories in both, with a different currency.
        public let currencies: [CurrencyChange]

        public var agrees: Bool { missingHere.isEmpty && missingThere.isEmpty && currencies.isEmpty }
    }

    /// `remote` maps each territory id to the currency App Store Connect gave.
    public static func compare(
        remote: [String: String?],
        table: [Territory] = Territory.all
    ) -> Outcome {
        let here = Dictionary(uniqueKeysWithValues: table.map { ($0.id, $0.currency) })
        let changes = table.sorted { $0.id < $1.id }.compactMap { territory -> CurrencyChange? in
            guard let there = remote[territory.id], there != territory.currency else { return nil }
            return CurrencyChange(territory: territory.id, table: territory.currency, appStoreConnect: there)
        }
        return Outcome(
            missingHere: Set(remote.keys).subtracting(here.keys).sorted(),
            missingThere: Set(here.keys).subtracting(remote.keys).sorted(),
            currencies: changes
        )
    }
}
