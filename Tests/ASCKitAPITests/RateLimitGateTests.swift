import Foundation
import Testing
@testable import ASCKitAPI

struct RateLimitGateTests {
    @Test func anOpenGateLetsARequestThroughAtOnce() async throws {
        let gate = RateLimitGate()
        let start = ContinuousClock.now

        try await gate.waitUntilOpen()

        #expect(ContinuousClock.now - start < .milliseconds(50))
    }

    /// A second refusal while a request already waits must hold that request
    /// too. Before, it woke at the first time and was refused again.
    @Test func aLongerWaitThatArrivesDuringASleepHoldsTheSleeper() async throws {
        let gate = RateLimitGate()
        let start = ContinuousClock.now
        await gate.close(for: .milliseconds(50))

        let waiter = Task { try await gate.waitUntilOpen() }
        // The waiter must be asleep on the first time before the second refusal.
        try await Task.sleep(for: .milliseconds(20))
        await gate.close(for: .milliseconds(250))
        try await waiter.value

        #expect(ContinuousClock.now - start >= .milliseconds(250))
    }
}
