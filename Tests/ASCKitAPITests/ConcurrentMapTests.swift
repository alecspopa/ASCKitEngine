import Foundation
import Synchronization
import Testing
@testable import ASCKitAPI

struct ConcurrentMapTests {
    /// Counts the pieces of work that run at the same time.
    final class Gauge: Sendable {
        private let counts = Mutex((open: 0, most: 0))

        var most: Int { counts.withLock { $0.most } }

        func enter() {
            counts.withLock {
                $0.open += 1
                $0.most = max($0.most, $0.open)
            }
        }

        func leave() {
            counts.withLock { $0.open -= 1 }
        }
    }

    @Test func keepsTheOrderOfTheElements() async throws {
        let doubled = try await Array(1 ... 20).concurrentMap { number in
            // The later ones finish first, so the order cannot come from when
            // they finish.
            try await Task.sleep(for: .milliseconds(20 - number))
            return number * 2
        }

        #expect(doubled == Array(1 ... 20).map { $0 * 2 })
    }

    @Test(arguments: [1, 3, 8])
    func runsNoMoreThanTheLimitAtOnce(limit: Int) async throws {
        let gauge = Gauge()

        _ = try await Array(0 ..< 24).concurrentMap(limit: limit) { _ in
            gauge.enter()
            defer { gauge.leave() }
            await Task.yield()
        }

        #expect(gauge.most <= limit)
    }

    /// A failure cancels nothing. The others run to their end, so the error
    /// thrown is the real one and not the cancellation it would cause.
    @Test func throwsTheRealFailureAndNotACancellation() async {
        let refusal = ASCError.forbidden(details: [])

        await #expect(throws: ASCError.self) {
            _ = try await [0, 1, 2].concurrentMap { index in
                if index == 0 { throw refusal }
                try await Task.sleep(for: .milliseconds(10))
                return index
            }
        }
    }

    @Test func mapsNothingToNothing() async throws {
        let none: [Int] = []
        #expect(try await none.concurrentMap { $0 }.isEmpty)
    }
}
