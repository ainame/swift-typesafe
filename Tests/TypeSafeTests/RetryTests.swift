import Foundation
import Testing
@testable import TypeSafe

@Test(arguments: [408, 429, 500, 503, 599, 400, 401, 403, 404, 409, 422])
func defaultRetryStatuses(status: Int) async throws {
    let mock = MockTransport { _, _ in response(#"{"message":"failed"}"#, status: status, headers: ["retry-after-ms": "0"]) }
    await #expect(throws: TypeSafeError.self) { _ = try await client(mock, retry: .init()).models.list() }
    let attempts = await mock.requests.count
    #expect(attempts == ([408, 429].contains(status) || status >= 500 ? 3 : 1))
}

@Test func retryHeadersAndRecovery() async throws {
    let mock = MockTransport { _, attempt in
        attempt < 3 ? response(status: 429, headers: ["retry-after-ms": "0"]) : response(modelsFixture)
    }
    let c = try TypeSafeClient(apiKey: "real", retry: .init(), headers: ["AUTHORIZATION": "wrong", "X-TypeSafe-Retry-Count": "99", "X-Test": "default"], transport: mock, environment: [:])
    _ = try await c.models.list(options: .init(headers: ["Authorization": "wrong-again", "x-test": "call"]))
    let requests = await mock.requests
    #expect(requests.map { $0.headers["x-typesafe-retry-count"] } == [nil, "1", "2"])
    #expect(requests.allSatisfy { $0.headers["authorization"] == "Bearer real" && $0.headers["x-test"] == "call" })
}

@Test func retryBudgetStopsBeforeServerDelay() async throws {
    let mock = MockTransport { _, _ in response(status: 429, headers: ["Retry-After": "60"]) }
    await #expect(throws: TypeSafeError.self) { _ = try await client(mock, retry: .init(timeout: 1)).models.list() }
    #expect(await mock.requests.count == 1)
}

@Test func perCallRetryReplacesClientPolicy() async throws {
    let mock = MockTransport { _, _ in response(status: 409) }
    let c = try client(mock, retry: .init(maxRetries: 0))
    await #expect(throws: TypeSafeError.self) {
        _ = try await c.models.list(options: .init(retry: .init(maxRetries: 2, backoffInitial: 0, httpStatuses: [409])))
    }
    #expect(await mock.requests.count == 3)
    await #expect(throws: TypeSafeError.self) { _ = try await c.models.list() }
    #expect(await mock.requests.count == 4)
}

@Test func timeoutRetriesAndCleansUpChildTasks() async throws {
    let mock = MockTransport { _, _ in
        try await Task.sleep(for: .seconds(60))
        return response(modelsFixture)
    }
    let c = try client(mock, retry: .init(maxRetries: 1, backoffInitial: 0))
    do {
        _ = try await c.models.list(options: .init(timeout: 0.02))
        Issue.record("Expected timeout")
    } catch TypeSafeError.timeout(let seconds) { #expect(seconds == 0.02) }
    #expect(await mock.requests.count == 2)
}

@Test func connectionFailureRetries() async throws {
    let mock = MockTransport { _, attempt in
        if attempt == 1 { throw URLError(.networkConnectionLost) }
        return response(modelsFixture)
    }
    _ = try await client(mock, retry: .init(backoffInitial: 0)).models.list()
    #expect(await mock.requests.count == 2)
}

@Test func cancellationDuringRequestNeverRetries() async throws {
    let (started, continuation) = AsyncStream<Void>.makeStream()
    let mock = MockTransport { _, _ in
        continuation.yield(())
        try await Task.sleep(for: .seconds(60))
        return response(modelsFixture)
    }
    let c = try client(mock, retry: .init(predicate: { _ in true }))
    let task = Task { try await c.models.list() }
    for await _ in started { break }
    task.cancel()
    await #expect(throws: CancellationError.self) { _ = try await task.value }
    #expect(await mock.requests.count == 1)
}

@Test func cancellationDuringBackoffNeverRetries() async throws {
    let (started, continuation) = AsyncStream<Void>.makeStream()
    let mock = MockTransport { _, _ in
        continuation.yield(())
        return response(status: 429, headers: ["retry-after": "60"])
    }
    let c = try client(mock, retry: .init(timeout: nil))
    let task = Task { try await c.models.list() }
    for await _ in started { break }
    // Cancellation is valid whether the first response is still returning or the sleep has begun.
    task.cancel()
    await #expect(throws: CancellationError.self) { _ = try await task.value }
    #expect(await mock.requests.count == 1)
}

@Test func concurrentCallsKeepIndependentRetryState() async throws {
    let mock = MockTransport { request, _ in
        request.headers["x-typesafe-retry-count"] == nil ? response(status: 429, headers: ["retry-after-ms": "0"]) : response(modelsFixture)
    }
    let c = try client(mock, retry: .init())
    try await withThrowingTaskGroup(of: Void.self) { group in
        for id in 0..<4 { group.addTask { _ = try await c.models.list(options: .init(headers: ["x-call": String(id)])) } }
        try await group.waitForAll()
    }
    let requests = await mock.requests
    for id in 0..<4 {
        #expect(requests.filter { $0.headers["x-call"] == String(id) }.map { $0.headers["x-typesafe-retry-count"] } == [nil, "1"])
    }
}

@Test func customRetryPredicate() async throws {
    let mock = MockTransport { _, attempt in attempt == 1 ? response("not JSON") : response(modelsFixture) }
    let policy = RetryPolicy(backoffInitial: 0, predicate: { if case TypeSafeError.responseValidation = $0 { true } else { false } })
    _ = try await client(mock, retry: policy).models.list()
    #expect(await mock.requests.count == 2)
}

@Test func backoffAndServerDelays() {
    let policy = RetryPolicy()
    let error = TypeSafeError.connection("offline")
    #expect((0...5).map { policy.delay(attempt: $0, error: error, random: 0) } == [0.5, 1, 2, 4, 5, 5])
    #expect(policy.delay(attempt: 0, error: error, random: 1) == 0.375)
    #expect(policy.delay(attempt: Int.max, error: error, random: 0) == 5)
    #expect(RetryPolicy(backoffInitial: 0).delay(attempt: 1, error: error) == 0)
    #expect(RetryPolicy(backoffMax: 0).delay(attempt: 1, error: error) == 0)
    let rateLimit = TypeSafeError.api(APIError(status: 429, body: .null, headers: ["Retry-After": "61"]))
    #expect(policy.delay(attempt: 0, error: rateLimit) == 61)
}

@Test(arguments: [
    (["retry-after-ms": "150", "Retry-After": "2"], 0.15),
    (["retry-after-ms": "NaN", "Retry-After": "1.5"], 1.5),
    (["retry-after-ms": "-1", "Retry-After": "2"], 2.0),
    (["Retry-After": ""], 0.0),
    (["Retry-After": "-1"], nil),
    (["retry-after-ms": "inf"], nil),
    (["Retry-After": "bad"], nil),
] as [([String: String], Double?)])
func retryAfterParsing(headers: [String: String], expected: Double?) { #expect(RetryPolicy.retryAfter(headers: headers) == expected) }

@Test func httpDateRetryAfter() {
    let now = Date(timeIntervalSince1970: 1_000_000)
    #expect(RetryPolicy.retryAfter(headers: ["Retry-After": "Mon, 12 Jan 1970 13:46:50 GMT"], now: now) == 10)
    #expect(RetryPolicy.retryAfter(headers: ["Retry-After": "Mon, 12 Jan 1970 13:46:30 GMT"], now: now) == 0)
}
