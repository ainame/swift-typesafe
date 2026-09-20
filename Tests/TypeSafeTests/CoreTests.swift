import Foundation
import Testing
@testable import TypeSafe

@Test func roundTripAllQuestions() async throws {
    let mock = MockTransport()
    let result = try await client(mock).systemOne(state: ["document": "Hello 🌍"], questions: [
        "spam": .noul(instructions: "Spam?"),
        "tone": .choice(instructions: "Tone?", criteria: ["friendly": nil, "hostile": nil]),
        "quality": .score(instructions: "Quality?", criteria: ["bad", "ok", "great"]),
    ])
    #expect(result.nouls["spam"]?.noul == 0.98)
    #expect(result.choices["tone"]?.choice == "friendly")
    #expect(result.scores["quality"]?.score == 1.7)
    #expect(result.scores["quality"]?.legend[2] == "great")
    #expect(result.scores["quality"]?.probabilities[2] == 0.8)
    #expect(result.usage.inputTokens == 12)
    #expect(result.requestID == "req_123")
    let request = try #require(await mock.requests.first)
    #expect(request.method == "POST")
    #expect(request.url.absoluteString == "https://api.typesafe.ai/v1/systemone")
    #expect(request.headers["authorization"] == "Bearer test-key")
    #expect(request.headers["content-type"] == "application/json")
    #expect(request.headers["x-typesafe-retry-count"] == nil)
    let body = try JSONDecoder().decode(JSONValue.self, from: #require(request.body))
    #expect(body["questions"]?["tone"]?["criteria"] == ["friendly": nil, "hostile": nil])
    let encoded = try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(result))
    #expect(encoded["requestID"] == nil)
    #expect(encoded["rawHTTPResponse"] == nil)
    #expect(encoded["answers"]?["quality"]?["type"] == "score")
}

@Test func modelsAndOptionalUsage() async throws {
    let mock = MockTransport { _, _ in response(modelsFixture) }
    let result = try await client(mock).models.list()
    #expect(result.models.first?.releaseDate == "2026-08-01")
    #expect(result.requestID == "req_123")
    #expect(await mock.requests.first?.body == nil)
    let decoded = try JSONDecoder().decode(SystemOneResponse.self, from: Data(#"{"model":"m","usage":{},"answers":{}}"#.utf8))
    #expect(decoded.usage.inputTokens == nil)
}

@Test func rawQuestionsAndShallowOverrides() async throws {
    let mock = MockTransport()
    _ = try await client(mock).systemOne(state: "original", questions: [
        "future": .raw(["type": "future", "instructions": nil, "extra": ["a": 1]]),
        "score": .score(criteria: ["only one"]),
    ], model: "call-model", extraBody: ["state": ["replacement": true], "model": "override", "nullable": nil])
    let request = try #require(await mock.requests.first)
    let body = try JSONDecoder().decode(JSONValue.self, from: #require(request.body))
    #expect(body["state"] == ["replacement": true])
    #expect(body["model"] == "override")
    #expect(body["nullable"] == .null)
    #expect(body["questions"]?["future"]?["instructions"] == .null)
}

@Test(arguments: [
    #"{"model":"m","usage":{},"answers":{"a":{"type":"noul"}}}"#,
    #"{"model":"m","usage":{},"answers":{"a":{"type":"noul","noul":"bad"}}}"#,
])
func malformedAnswerPaths(json: String) async throws {
    let mock = MockTransport { _, _ in response(json) }
    do {
        _ = try await client(mock).systemOne(state: "s", questions: ["a": .noul()])
        Issue.record("Expected response validation failure")
    } catch TypeSafeError.responseValidation(let api, let fieldPath) {
        #expect(fieldPath == "answers.a.noul")
        #expect(api.status == 200)
        #expect(api.requestID == "req_123")
    }
}

@Test func unknownAnswersAreSkippedAndRetainedInRawBody() async throws {
    let json = #"{"model":"m","usage":{},"answers":{"future":{"type":"future","x":1},"a":{"type":"noul","noul":0.5,"extra":true}},"extra":true}"#
    let mock = MockTransport { _, _ in response(json) }
    let result = try await client(mock).systemOne(state: "s", questions: ["a": .noul()])
    #expect(result.answers.count == 1)
    #expect(result.rawHTTPResponse?.body == Data(json.utf8))
}

private struct KnownAnswers: Decodable, Sendable {
    let spam: NoulAnswer
}

private struct KnownResponse: Decodable, Sendable {
    let model: String
    let answers: KnownAnswers
}

@Test func customResponseModelDecodesKnownFields() async throws {
    let result = try await client().systemOne(
        state: "message", questions: ["spam": .noul()], responseModel: KnownResponse.self
    )
    #expect(result.model == "jev-latest")
    #expect(result.answers.spam.noul == 0.98)
}

@Test func customResponseModelReportsValidationPath() async throws {
    let mock = MockTransport { _, _ in response(#"{"model":"m","usage":{},"answers":{"spam":{"type":"noul"}}}"#) }
    do {
        _ = try await client(mock).systemOne(state: "message", questions: ["spam": .noul()], responseModel: KnownResponse.self)
        Issue.record("Expected response validation failure")
    } catch TypeSafeError.responseValidation(let api, let fieldPath) {
        #expect(fieldPath == "answers.spam.noul")
        #expect(api.requestID == "req_123")
    }
}

@Test func customResponseModelPreservesAPIError() async throws {
    let mock = MockTransport { _, _ in response(#"{"detail":"Invalid request"}"#, status: 400) }
    do {
        _ = try await client(mock).systemOne(state: "message", questions: ["spam": .noul()], responseModel: KnownResponse.self)
        Issue.record("Expected API error")
    } catch TypeSafeError.api(let error) {
        #expect(error.kind == .badRequest)
        #expect(error.requestID == "req_123")
    }
}
