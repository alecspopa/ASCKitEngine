import Foundation

/// How many reads of one kind go out at the same time.
///
/// A listing in forty languages would otherwise send forty requests in one
/// burst, and a rate limit met by all of them is forty requests to wait out.
let concurrentReadLimit = 8

extension Collection where Element: Sendable {
    /// The transform of every element, read at the same time, in the order of
    /// the elements.
    ///
    /// At most `limit` run at once. Each one that finishes starts the next.
    ///
    /// Every child runs to its end, win or lose. A child that throws would
    /// cancel its siblings, and a cancelled sibling then reports `cancelled`
    /// rather than the reason for it. So the error thrown is the most telling
    /// one of all that failed.
    func concurrentMap<Value: Sendable>(
        limit: Int = concurrentReadLimit,
        _ transform: @escaping @Sendable (Element) async throws -> Value
    ) async throws -> [Value] {
        let items = Array(self)
        let outcomes = await withTaskGroup(of: (Int, Result<Value, any Error>).self) { group in
            var outcomes = [Result<Value, any Error>?](repeating: nil, count: items.count)
            var next = 0

            func startNext() {
                guard next < items.count else { return }
                let index = next
                let item = items[index]
                next += 1
                group.addTask { await (index, captured { try await transform(item) }) }
            }

            for _ in 0 ..< Swift.max(1, limit) {
                startNext()
            }
            while let (index, outcome) = await group.next() {
                outcomes[index] = outcome
                startNext()
            }
            return outcomes.compactMap(\.self)
        }
        return try unwrap(outcomes)
    }
}

/// Runs one piece of work and keeps whatever it did, win or lose.
private func captured<Value: Sendable>(_ work: () async throws -> Value) async -> Result<Value, any Error> {
    do {
        return try await .success(work())
    } catch {
        return .failure(error)
    }
}

/// Everything that worked, or the failure worth showing.
private func unwrap<Value>(_ outcomes: [Result<Value, any Error>]) throws -> [Value] {
    let failures = outcomes.compactMap(\.failure)
    if let error = failures.mostTelling { throw error }
    return outcomes.compactMap(\.success)
}

extension Result {
    var success: Success? {
        guard case let .success(value) = self else { return nil }
        return value
    }

    var failure: Failure? {
        guard case let .failure(error) = self else { return nil }
        return error
    }
}
