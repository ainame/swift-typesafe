import Foundation
import Testing
@testable import TypeSafe

@Test(arguments: ["default", "environment", "explicit"])
func configurationPrecedence(source: String) async throws {
    let mock = MockTransport()
    let env = source == "default" ? [:] : ["TYPESAFE_API_KEY": " env-key ", "TYPESAFE_BASE_URL": " https://env.test/// ", "TYPESAFE_DEFAULT_MODEL": " env-model "]
    let c = try TypeSafeClient(apiKey: source == "explicit" ? "code-key" : source == "default" ? "test-key" : nil,
        baseURL: source == "explicit" ? "https://code.test///" : nil,
        model: source == "explicit" ? "code-model" : nil, transport: mock, environment: env)
    _ = try await c.systemOne(state: "hello", questions: ["q": .noul()])
    let request = try #require(await mock.requests.first)
    let body = try JSONDecoder().decode(JSONValue.self, from: #require(request.body))
    #expect(request.headers["authorization"] == "Bearer " + (source == "explicit" ? "code-key" : source == "environment" ? "env-key" : "test-key"))
    #expect(body["model"] == .string(source == "explicit" ? "code-model" : source == "environment" ? "env-model" : "jev-latest"))
    #expect(request.url.absoluteString == (source == "explicit" ? "https://code.test" : source == "environment" ? "https://env.test" : "https://api.typesafe.ai") + "/v1/systemone")
    #expect(request.timeout == 10)
}

@Test func blankEnvironmentAndMissingKey() throws {
    #expect(throws: TypeSafeError.self) { try TypeSafeClient(environment: [:]) }
    #expect(throws: TypeSafeError.self) { try TypeSafeClient(environment: ["TYPESAFE_API_KEY": " \t\n "]) }
    let c = try TypeSafeClient(apiKey: "key", environment: ["TYPESAFE_BASE_URL": " \t ", "TYPESAFE_DEFAULT_MODEL": " "])
    #expect(c.baseURL == TypeSafeClient.defaultBaseURL)
    #expect(c.model == TypeSafeClient.defaultModel)
    #expect(!String(describing: c).contains("key"))
}

@Test(arguments: ["", " \t\r\n ", "pre fix", "pre\tfix", "pre\nfix", "pre\u{0}fix", "pre\u{7f}fix", "précis"])
func invalidAPIKeysDoNotFallBackToEnvironment(key: String) throws {
    #expect(throws: TypeSafeError.self) {
        try TypeSafeClient(apiKey: key, environment: ["TYPESAFE_API_KEY": "valid-env-key"])
    }
    #expect(throws: TypeSafeError.self) {
        try TypeSafeClient(environment: ["TYPESAFE_API_KEY": key])
    }
}

@Test(arguments: ["\n", "\r\n", " \t\r\n "])
func APIKeyPaddingIsTrimmed(padding: String) async throws {
    let mock = MockTransport { _, _ in response(modelsFixture) }
    let c = try TypeSafeClient(apiKey: "\(padding)test-key\(padding)", transport: mock, environment: [:])
    _ = try await c.models.list()
    #expect(await mock.requests.first?.headers["authorization"] == "Bearer test-key")
}

@Test(arguments: [0.0, -1, .infinity, .nan])
func invalidTimeoutsFailBeforeNetwork(value: Double) async throws {
    #expect(throws: TypeSafeError.self) { try TypeSafeClient(apiKey: "k", timeout: value) }
    let mock = MockTransport()
    let c = try client(mock)
    await #expect(throws: TypeSafeError.self) { _ = try await c.models.list(options: .init(timeout: value)) }
    #expect(await mock.requests.isEmpty)
}

@Test func invalidRetrySettings() throws {
    for policy in [RetryPolicy(maxRetries: -1), RetryPolicy(backoffInitial: -.infinity), RetryPolicy(backoffMax: -1),
                   RetryPolicy(backoffJitter: .nan), RetryPolicy(backoffJitter: 1.1), RetryPolicy(timeout: 0)] {
        #expect(throws: TypeSafeError.self) { try policy.validate() }
    }
}

@Test func invalidQuestionsFailBeforeNetwork() async throws {
    let mock = MockTransport()
    for questions: [String: Question] in [[:], ["q": .raw([:])], ["q": .raw(["type": ""])],
                                        ["q": .raw(["type": "choice"])], ["q": .score(criteria: [])]] {
        await #expect(throws: TypeSafeError.self) { _ = try await client(mock).systemOne(state: "s", questions: questions) }
    }
    await #expect(throws: TypeSafeError.self) { _ = try await client(mock).systemOne(state: .null, questions: ["q": .noul()]) }
    await #expect(throws: TypeSafeError.self) { _ = try await client(mock).systemOne(state: ["invalid": .number(.nan)], questions: ["q": .noul()]) }
    #expect(await mock.requests.isEmpty)
}

@Test func optionalDescriptionsAndNestedJSON() async throws {
    let mock = MockTransport()
    _ = try await client(mock).systemOne(state: ["first", ["second": nil]], questions: [
        "omitted": .noul(), "explicit": .raw(["type": "noul", "instructions": nil, "criteria": nil]),
        "rich": .choice(instructions: ["question": "Which?"], criteria: ["one": ["examples": ["a", nil]], "two": nil]),
    ], model: "custom", options: .init(timeout: 2))
    let request = try #require(await mock.requests.first)
    let body = try JSONDecoder().decode(JSONValue.self, from: #require(request.body))
    #expect(body["questions"]?["omitted"]?["instructions"] == nil)
    #expect(body["questions"]?["explicit"]?["instructions"] == .null)
    #expect(body["questions"]?["rich"]?["criteria"]?["one"] == ["examples": ["a", nil]])
    #expect(body["model"] == "custom")
    #expect(request.timeout == 2)
}

@Test func integerJSONRoundTrip() throws {
    let value: JSONValue = ["large": .integer(Int64.max), "bool": true, "null": nil, "nested": [1, "s", false]]
    #expect(try JSONDecoder().decode(JSONValue.self, from: JSONEncoder().encode(value)) == value)
}
