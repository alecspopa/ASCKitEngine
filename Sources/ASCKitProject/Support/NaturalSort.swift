import Foundation

extension StringProtocol {
    /// Numbers inside the text count by value, so `2.png` comes before `10.png`.
    func isNaturallyBefore(_ other: some StringProtocol) -> Bool {
        compare(other, options: .numeric) == .orderedAscending
    }
}

extension Sequence<URL> {
    func sortedNaturally(by key: KeyPath<URL, String> = \.lastPathComponent) -> [URL] {
        sorted { $0[keyPath: key].isNaturallyBefore($1[keyPath: key]) }
    }
}
