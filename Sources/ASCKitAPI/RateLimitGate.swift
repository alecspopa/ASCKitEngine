import Foundation

/// Holds requests back for as long as App Store Connect asked.
///
/// Reading a listing asks for every language at once, so one refusal arrives
/// while several other requests are still in flight. Each of them finding out
/// on its own is another round against a limit that already said no, so the
/// wait is kept in one place and all of them sit through it.
actor RateLimitGate {
    private var openAt: ContinuousClock.Instant?

    /// Nothing goes out until this much time has passed.
    ///
    /// The later of the two waits wins. A shorter one arriving second must not
    /// let everything through early.
    func close(for wait: Duration) {
        let instant = ContinuousClock.now.advanced(by: wait)
        openAt = openAt.map { Swift.max($0, instant) } ?? instant
    }

    /// Returns at once while the gate is open, which is the usual case.
    func waitUntilOpen() async throws {
        guard let openAt else { return }
        try await Task.sleep(until: openAt, clock: .continuous)
    }
}
