import Foundation
import Testing
@testable import TypeSafe

@Test(arguments: [(400, APIError.Kind.badRequest), (401, .authentication), (403, .permissionDenied), (404, .notFound), (422, .unprocessableEntity), (429, .rateLimit), (500, .internalServer), (302, .other)])
func statusErrorMapping(status: Int, kind: APIError.Kind) async throws {
    let mock = MockTransport { _, _ in response(#"{"error":{"message":"failure"}}"#, status: status) }
    do { _ = try await client(mock).models.list(); Issue.record("Expected API failure") }
    catch TypeSafeError.api(let error) {
        #expect(error.kind == kind)
        #expect(error.status == status)
        #expect(error.requestID == "req_123")
        #expect(error.description.contains("GET https://api.typesafe.ai/v1/models"))
        #expect(error.message == "failure")
        #expect(error.body["error"]?["message"] == "failure")
    }
}

@Test(arguments: [
    (#"{"error":"first","message":"second"}"#, "first"),
    (#"{"detail":{"message":"detail"}}"#, "detail"),
    (#"{"detail":[{"loc":["body","questions","q",0],"msg":"invalid"}]}"#, "questions.q.0: invalid"),
    ("plain text", "plain text"),
    ("", "status code (no body)"),
])
func apiErrorMessages(body: String, expected: String) async throws {
    let mock = MockTransport { _, _ in response(body, status: 400) }
    do { _ = try await client(mock).models.list(); Issue.record("Expected API failure") }
    catch TypeSafeError.api(let error) { #expect(error.message == expected) }
}

@Test func sanitizedEndpoint() async throws {
    let mock = MockTransport { _, _ in response(status: 401) }
    let c = try TypeSafeClient(apiKey: "secret-key", baseURL: "https://name:secret-password@example.test", retry: .init(maxRetries: 0), transport: mock, environment: [:])
    do { _ = try await c.models.list(); Issue.record("Expected API failure") }
    catch TypeSafeError.api(let error) {
        #expect(error.endpoint == "GET https://example.test/v1/models")
        #expect(!error.description.contains("secret"))
    }
}

@Test(arguments: ["name", "description", "release_date"])
func nestedModelValidationPath(field: String) async throws {
    var invalid: [String: JSONValue] = ["name": "m", "description": "d", "release_date": "today"]
    invalid.removeValue(forKey: field)
    let data = try JSONEncoder().encode(JSONValue.object(["models": .array([.object(["name": "m", "description": "d", "release_date": "today"]), .object(invalid)])]))
    let mock = MockTransport { _, _ in RawHTTPResponse(status: 200, body: data) }
    do { _ = try await client(mock).models.list(); Issue.record("Expected validation failure") }
    catch TypeSafeError.responseValidation(_, let path) { #expect(path == "models[1].\(field)") }
}

@Test func malformedResponseDoesNotRetryByDefault() async throws {
    let mock = MockTransport { _, _ in response("not JSON") }
    await #expect(throws: TypeSafeError.self) { _ = try await client(mock, retry: .init(backoffInitial: 0)).models.list() }
    #expect(await mock.requests.count == 1)
}

@Test(arguments: ["[]", #"{"x":"invalid key"}"#, #"{"0":null}"#])
func scoreLegendRequiresIntegerKeyedContent(legend: String) async throws {
    let json = "{\"model\":\"m\",\"usage\":{},\"answers\":{\"q\":{\"type\":\"score\",\"score\":0,\"confidence\":1,\"legend\":\(legend),\"probabilities\":{}}}}"
    let mock = MockTransport { _, _ in response(json) }
    await #expect(throws: TypeSafeError.self) { _ = try await client(mock).systemOne(state: "s", questions: ["q": .score(criteria: ["one"])]) }
}
