import ASCKitTestSupport
import Foundation
import Testing
@testable import ASCKitAPI

struct ASCClientTests {
    @Test func attachesTheTokenAsABearerHeader() async throws {
        let transport = StubTransport(.ok(#"{"data":[]}"#))
        let client = try ASCClient.stubbed(transport: transport)

        _ = try await client.app(bundleID: "com.example.MyApp")

        let authorization = await transport.request(at: 0).value(forHTTPHeaderField: "Authorization")
        #expect(authorization?.hasPrefix("Bearer ") == true)
    }

    @Test func looksUpAnAppByBundleIdentifier() async throws {
        let json = """
        {"data":[{"type":"apps","id":"1234","attributes":{"name":"My App","bundleId":"com.example.MyApp"}}]}
        """
        let transport = StubTransport(.ok(json))
        let client = try ASCClient.stubbed(transport: transport)

        let app = try await client.app(bundleID: "com.example.MyApp")

        #expect(app?.id == "1234")
        #expect(app?.attributes?.name == "My App")

        let url = try #require(await transport.request(at: 0).url?.absoluteString)
        #expect(url.contains("filter%5BbundleId%5D=com.example.MyApp"))
    }

    @Test func returnsNoAppWhenNothingMatches() async throws {
        let client = try ASCClient.stubbed(transport: StubTransport(.ok(#"{"data":[]}"#)))
        #expect(try await client.app(bundleID: "com.example.Missing") == nil)
    }

    @Test func followsPagingToTheEnd() async throws {
        let firstPage = """
        {"data":[{"type":"apps","id":"1","attributes":{}}],
         "links":{"next":"https://api.example.test/v1/apps?cursor=2"}}
        """
        let secondPage = """
        {"data":[{"type":"apps","id":"2","attributes":{}}],"links":{}}
        """
        let transport = StubTransport([.ok(firstPage), .ok(secondPage)])
        let client = try ASCClient.stubbed(transport: transport)

        let apps = try await client.list("/v1/apps", as: AppAttributes.self)

        #expect(apps.map(\.id) == ["1", "2"])
        #expect(await transport.requestCount == 2)
        #expect(await transport.request(at: 1).url?.query?.contains("cursor=2") == true)
    }

    /// An app has more than one appInfo. Writing the name to the live one is a
    /// 409, so the client has to pick the editable one.
    @Test func picksTheEditableAppInfo() async throws {
        let json = """
        {"data":[
          {"type":"appInfos","id":"live","attributes":{"state":"READY_FOR_DISTRIBUTION"}},
          {"type":"appInfos","id":"draft","attributes":{"state":"PREPARE_FOR_SUBMISSION"}}
        ]}
        """
        let client = try ASCClient.stubbed(transport: StubTransport(.ok(json)))
        #expect(try await client.editableAppInfo(appID: "1")?.id == "draft")
    }

    @Test func findsNoEditableAppInfoWhenEverythingIsLive() async throws {
        let json = """
        {"data":[{"type":"appInfos","id":"live","attributes":{"state":"READY_FOR_DISTRIBUTION"}}]}
        """
        let client = try ASCClient.stubbed(transport: StubTransport(.ok(json)))
        #expect(try await client.editableAppInfo(appID: "1") == nil)
    }

    @Test func picksTheVersionThatStillAcceptsChanges() async throws {
        let json = """
        {"data":[
          {"type":"appStoreVersions","id":"live",
           "attributes":{"versionString":"1.0","appVersionState":"READY_FOR_DISTRIBUTION"}},
          {"type":"appStoreVersions","id":"next",
           "attributes":{"versionString":"1.1","appVersionState":"PREPARE_FOR_SUBMISSION"}}
        ]}
        """
        let client = try ASCClient.stubbed(transport: StubTransport(.ok(json)))
        #expect(try await client.editableVersion(appID: "1")?.id == "next")
    }

    @Test func refusesAVersionStringThatIsNotEditable() async throws {
        let json = """
        {"data":[
          {"type":"appStoreVersions","id":"live",
           "attributes":{"versionString":"1.0","appVersionState":"READY_FOR_DISTRIBUTION"}},
          {"type":"appStoreVersions","id":"next",
           "attributes":{"versionString":"1.1","appVersionState":"PREPARE_FOR_SUBMISSION"}}
        ]}
        """
        let client = try ASCClient.stubbed(transport: StubTransport(.ok(json)))
        #expect(try await client.editableVersion(appID: "1", versionString: "1.0") == nil)
    }

    @Test func sendsTheVersionCreateBodyAppleExpects() async throws {
        let reply = """
        {"data":{"type":"appStoreVersions","id":"new","attributes":{"versionString":"1.1"}}}
        """
        let transport = StubTransport(.ok(reply))
        let client = try ASCClient.stubbed(transport: transport)

        _ = try await client.createVersion(appID: "1234", versionString: "1.1")

        let request = await transport.request(at: 0)
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")

        let body = try #require(request.httpBody)
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let data = try #require(json["data"] as? [String: Any])
        let attributes = try #require(data["attributes"] as? [String: Any])
        let relationships = try #require(data["relationships"] as? [String: Any])
        let app = try #require(relationships["app"] as? [String: Any])

        #expect(data["type"] as? String == "appStoreVersions")
        #expect(attributes["platform"] as? String == "IOS")
        #expect(attributes["versionString"] as? String == "1.1")
        #expect((app["data"] as? [String: Any])?["id"] as? String == "1234")
    }

    // MARK: - When the network gets in the way

    /// A connection that drops is the one failure a second attempt usually
    /// gets past, and it used to reach a person as an NSError dump instead.
    @Test func triesADroppedConnectionAgain() async throws {
        let transport = StubTransport([
            .networkFailure(.networkConnectionLost),
            .ok(#"{"data":[]}"#)
        ])
        let client = try ASCClient.stubbed(transport: transport, retryPolicy: .immediate)

        _ = try await client.app(bundleID: "com.example.MyApp")

        #expect(await transport.requestCount == 2)
    }

    @Test func givesUpOnANetworkFaultThatWillNotChange() async throws {
        let transport = StubTransport([
            .networkFailure(.secureConnectionFailed),
            .ok(#"{"data":[]}"#)
        ])
        let client = try ASCClient.stubbed(transport: transport, retryPolicy: .immediate)

        await #expect(throws: ASCError.self) {
            _ = try await client.app(bundleID: "com.example.MyApp")
        }
        #expect(await transport.requestCount == 1)
    }

    /// A cancelled request is this app stopping its own work. It carries no
    /// news, so it must not arrive looking like something App Store Connect did.
    @Test func reportsACancelledRequestAsACancellation() async throws {
        let transport = StubTransport(.networkFailure(.cancelled))
        let client = try ASCClient.stubbed(transport: transport, retryPolicy: .immediate)

        await #expect(throws: CancellationError.self) {
            _ = try await client.app(bundleID: "com.example.MyApp")
        }
        #expect(await transport.requestCount == 1)
    }

    @Test func saysWhatWentWrongWithoutTheErrorDump() async throws {
        let transport = StubTransport(.networkFailure(.timedOut))
        let client = try ASCClient.stubbed(transport: transport, retryPolicy: .none)

        let thrown = await #expect(throws: ASCError.self) {
            _ = try await client.app(bundleID: "com.example.MyApp")
        }

        let text = try #require(thrown).description
        #expect(text == "App Store Connect took too long to answer. Try again.")
    }

    // MARK: - Doing what App Store Connect asked

    /// The wait is short here so the test is short. Apple sends whole seconds.
    @Test func waitsAsLongAsAppStoreConnectAsked() async throws {
        let transport = StubTransport([
            .failure(429, headers: ["Retry-After": "0.2"]),
            .ok(#"{"data":[]}"#)
        ])
        let client = try ASCClient.stubbed(transport: transport, retryPolicy: .immediate)

        let started = ContinuousClock.now
        _ = try await client.app(bundleID: "com.example.MyApp")
        let took = ContinuousClock.now - started

        #expect(await transport.requestCount == 2)
        #expect(took >= .milliseconds(200), "went again before the wait was up")
    }

    /// Ten minutes of a window doing nothing reads as a window that broke, so
    /// the wait is reported rather than sat through.
    @Test func refusesToSitThroughAWaitNobodyWouldWatch() async throws {
        let transport = StubTransport([
            .failure(429, headers: ["Retry-After": "600"]),
            .ok(#"{"data":[]}"#)
        ])
        let client = try ASCClient.stubbed(transport: transport, retryPolicy: .immediate)

        let thrown = await #expect(throws: ASCError.self) {
            _ = try await client.app(bundleID: "com.example.MyApp")
        }

        #expect(await transport.requestCount == 1)
        #expect(try #require(thrown).description.contains("try again in 10 minutes"))
    }

    /// The ceiling is a minute. A wait past it goes to the person, who can
    /// press the button again whenever it suits them.
    @Test func sitsThroughAMinuteAndNotAMinuteAndAHalf() async throws {
        let transport = StubTransport([
            .failure(429, headers: ["Retry-After": "90"]),
            .ok(#"{"data":[]}"#)
        ])
        let client = try ASCClient.stubbed(transport: transport, retryPolicy: .immediate)

        await #expect(throws: ASCError.self) {
            _ = try await client.app(bundleID: "com.example.MyApp")
        }
        #expect(await transport.requestCount == 1)
        #expect(RetryPolicy().maximumWait == .seconds(60))
    }

    /// Being told to wait twice is App Store Connect saying come back later,
    /// which is not the same as saying try harder.
    @Test func waitsOutOneRateLimitAndNoMore() async throws {
        let transport = StubTransport([
            .failure(429, headers: ["Retry-After": "0.05"]),
            .failure(429, headers: ["Retry-After": "0.05"]),
            .ok(#"{"data":[]}"#)
        ])
        let client = try ASCClient.stubbed(transport: transport, retryPolicy: .immediate)

        await #expect(throws: ASCError.self) {
            _ = try await client.app(bundleID: "com.example.MyApp")
        }
        #expect(await transport.requestCount == 2)
    }

    /// With no wait named there is nothing to respect, so the backoff decides.
    @Test func triesAgainOnARateLimitThatNamesNoWait() async throws {
        let transport = StubTransport([
            .failure(429, headers: ["X-Rate-Limit": "user-hour-lim:3500;user-hour-rem:0;"]),
            .ok(#"{"data":[]}"#)
        ])
        let client = try ASCClient.stubbed(transport: transport, retryPolicy: .immediate)

        _ = try await client.app(bundleID: "com.example.MyApp")

        #expect(await transport.requestCount == 2)
    }

    /// The window shows a spinner while this waits, so it has to be able to say
    /// what it is waiting for.
    @Test func saysWhenItStartsWaitingAndWhenItStops() async throws {
        let transport = StubTransport([
            .failure(429, headers: ["Retry-After": "0.05"]),
            .ok(#"{"data":[]}"#)
        ])

        // Counted as it happens rather than read afterwards. The client says
        // both of these from inside the request, so waiting for a clock to
        // catch up would only make the test slow and flaky.
        try await confirmation("it says a wait started") { started in
            try await confirmation("it says the wait is over", expectedCount: 1...) { stopped in
                let client = try ASCClient.stubbed(transport: transport, retryPolicy: .immediate)
                    .reportingWaits { wait in
                        guard let wait else {
                            stopped()
                            return
                        }
                        #expect(wait == .milliseconds(50))
                        started()
                    }

                _ = try await client.app(bundleID: "com.example.MyApp")
            }
        }
    }

    // MARK: - A token refused for its shape

    /// The refusal a project with no Issuer ID gets, which Apple only
    /// ever calls NOT_AUTHORIZED.
    static let notAuthorized = #"""
    {"errors":[{"status":"401","code":"NOT_AUTHORIZED","title":"Authentication credentials are missing or invalid."}]}
    """#

    @Test func namesTheMissingIssuerWhenAnIndividualKeyIsRefused() async throws {
        let transport = StubTransport(.failure(401, Self.notAuthorized))
        let client = try ASCClient.stubbed(transport: transport, kind: .individual)

        let error = await #expect(throws: ASCError.self) {
            try await client.app(bundleID: "com.example.MyApp")
        }

        let refusal = try #require(error)
        guard case .unauthorizedIndividualKey = refusal else {
            Issue.record("Expected the individual key case, got \(refusal)")
            return
        }
        #expect("\(refusal)".contains("Issuer ID"))
    }

    /// A team key refused for some other reason keeps the plain message. Saying
    /// the Issuer ID is missing when it is right there would send the
    /// person to change a setting that is already correct.
    @Test func leavesATeamKeyRefusalAlone() async throws {
        let transport = StubTransport(.failure(401, Self.notAuthorized))
        let client = try ASCClient.stubbed(transport: transport)

        let error = await #expect(throws: ASCError.self) {
            try await client.app(bundleID: "com.example.MyApp")
        }

        let refusal = try #require(error)
        guard case .unauthorized = refusal else {
            Issue.record("Expected the plain case, got \(refusal)")
            return
        }
    }

    /// Signing again produces the same shape, so a second request would only
    /// collect a second refusal.
    @Test func doesNotTryAgainWhenTheTokenNamedNoIssuer() async throws {
        let transport = StubTransport([
            .failure(401, Self.notAuthorized),
            .failure(401, Self.notAuthorized)
        ])
        let client = try ASCClient.stubbed(
            transport: transport,
            retryPolicy: .immediate,
            kind: .individual
        )

        _ = await #expect(throws: ASCError.self) {
            try await client.app(bundleID: "com.example.MyApp")
        }
        #expect(await transport.requests.count == 1)
    }
}
