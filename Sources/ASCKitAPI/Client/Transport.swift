import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// The seam that keeps Apple out of the tests.
///
/// Everything above this protocol is pure logic, so the whole client can be
/// exercised against recorded responses without a network connection.
public protocol Transport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
}

public struct URLSessionTransport: Transport {
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ASCError.notAnHTTPResponse
        }
        return (data, http)
    }
}
