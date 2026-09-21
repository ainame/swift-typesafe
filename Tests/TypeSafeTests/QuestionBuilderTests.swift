import Foundation
import Testing
import TypeSafe

private let builderFixture = resultFixture
    .replacingOccurrences(of: "\"tone\":", with: "\"question_0\":")
    .replacingOccurrences(of: "\"spam\":", with: "\"question_1\":")
    .replacingOccurrences(of: "\"quality\":", with: "\"question_2\":")

@Test func builderReturnsFlattenedTypedAnswers() async throws {
    let mock = MockTransport { _, _ in response(builderFixture) }
    let (tone, spam, quality) = try await client(mock).systemOne(state: "Hello") {
        Choice<Tone>("Tone?")
        Noul("Spam?")
        Score("Quality?", criteria: ["bad", "ok", "great"])
    }
    let _: ChoiceAnswer<Tone> = tone
    let _: NoulAnswer = spam
    let _: ScoreAnswer = quality
    #expect(tone == ChoiceAnswer(choice: .friendly, confidence: 0.9, probabilities: [.friendly: 0.9, .hostile: 0.1]))
    #expect(spam == NoulAnswer(noul: 0.98))
    #expect(quality == ScoreAnswer(score: 1.7, confidence: 0.8, legend: [0: "bad", 1: "ok", 2: "great"],
                                  probabilities: [0: 0.1, 1: 0.1, 2: 0.8]))
    #expect(await mock.requests.count == 1)
    let request = try #require(await mock.requests.first)
    let body = try JSONDecoder().decode(JSONValue.self, from: #require(request.body))
    #expect(body == [
        "state": "Hello", "model": "jev-latest", "questions": [
            "question_0": ["type": "choice", "instructions": "Tone?", "criteria": ["friendly": nil, "hostile": nil]],
            "question_1": ["type": "noul", "instructions": "Spam?"],
            "question_2": ["type": "score", "instructions": "Quality?", "criteria": ["bad", "ok", "great"]],
        ],
    ])
}

@Test func builderSingleAnswerAndRepeatedQuestionTypes() async throws {
    let json = #"{"model":"m","usage":{},"answers":{"question_0":{"type":"noul","noul":0.2},"question_1":{"type":"noul","noul":0.8}}}"#
    let mock = MockTransport { _, _ in response(json) }
    let single = try await client(mock).systemOne(state: "s") { Noul() }
    let _: NoulAnswer = single
    #expect(single.noul == 0.2)
    let (first, second) = try await client(mock).systemOne(state: "s") {
        Noul("First?")
        Noul("Second?")
    }
    #expect(first.noul == 0.2)
    #expect(second.noul == 0.8)
}

@QuestionBuilder
private func localQuestions() -> Questions<(ChoiceAnswer<Tone>, NoulAnswer, ScoreAnswer)> {
    Choice<Tone>("Tone?")
    Noul("Spam?")
    Score("Quality?", criteria: ["bad", "ok", "great"])
}

@Test func builderSupportsExplicitAnswerTypesAndComposition() async throws {
    let mock = MockTransport { _, _ in response(builderFixture) }
    let c = try client(mock)
    let (tone, spam, quality): (ChoiceAnswer<Tone>, NoulAnswer, ScoreAnswer) = try await c.systemOne(state: "s") {
        Choice<Tone>()
        Noul()
        Score(criteria: ["bad", "ok", "great"])
    }
    let reused = try await c.systemOne(state: "s", questions: localQuestions)
    #expect(reused.0 == tone)
    #expect(reused.1 == spam)
    #expect(reused.2 == quality)
}

@Test func builderHasNoFixedArityLimit() async throws {
    let answers = (0..<12).map { "\"question_\($0)\":{\"type\":\"noul\",\"noul\":\(Double($0) / 12)}" }.joined(separator: ",")
    let json = "{\"model\":\"m\",\"usage\":{},\"answers\":{\(answers)}}"
    let mock = MockTransport { _, _ in response(json) }
    let values = try await client(mock).systemOne(state: "s") {
        Noul(); Noul(); Noul(); Noul(); Noul(); Noul()
        Noul(); Noul(); Noul(); Noul(); Noul(); Noul()
    }
    #expect(values.0.noul == 0)
    #expect(values.9.noul == 9.0 / 12)
    #expect(values.10.noul == 10.0 / 12)
    #expect(values.11.noul == 11.0 / 12)
    let request = try #require(await mock.requests.first)
    let body = try JSONDecoder().decode([String: JSONValue].self, from: #require(request.body))
    guard case .object(let questions) = body["questions"] else {
        Issue.record("Expected a question object")
        return
    }
    #expect(questions.count == 12)
}

@Test func builderSupportsRichDescriptionsAndRequestOptions() async throws {
    let mock = MockTransport { _, _ in response(builderFixture) }
    _ = try await client(mock).systemOne(
        state: ["document": "Hello"], model: "custom",
        extraBody: ["state": ["replacement"], "extension": true],
        options: .init(timeout: 2, headers: ["x-project": "builder"])
    ) {
        Choice<Tone>(["question": "Tone?"], criteria: ["friendly": ["examples": ["hi"]], "hostile": nil])
        Noul(criteria: ["true": "Spam", "false": "Not spam"])
        Score(criteria: [["description": "Only criterion"]])
    }
    let request = try #require(await mock.requests.first)
    #expect(request.timeout == 2)
    #expect(request.headers["x-project"] == "builder")
    let body = try JSONDecoder().decode(JSONValue.self, from: #require(request.body))
    #expect(body["state"] == ["replacement"])
    #expect(body["model"] == "custom")
    #expect(body["extension"] == true)
    #expect(body["questions"] == [
        "question_0": ["type": "choice", "instructions": ["question": "Tone?"],
                       "criteria": ["friendly": ["examples": ["hi"]], "hostile": nil]],
        "question_1": ["type": "noul", "criteria": ["true": "Spam", "false": "Not spam"]],
        "question_2": ["type": "score", "criteria": [["description": "Only criterion"]]],
    ])
}

@Test func builderValidatesBeforeSending() async throws {
    let mock = MockTransport()
    let c = try client(mock)
    await #expect {
        try await c.systemOne(state: "s") {}
    } throws: { error in
        guard case TypeSafeError.configuration(let message) = error else { return false }
        return message == "At least one question is required."
    }
    await #expect {
        _ = try await c.systemOne(state: "s") { Score(criteria: []) }
    } throws: { error in
        guard case TypeSafeError.configuration(let message) = error else { return false }
        return message == "Score question 'question_0' requires at least one criterion."
    }
    await #expect {
        _ = try await c.systemOne(state: .null) { Noul() }
    } throws: { error in
        guard case TypeSafeError.configuration(let message) = error else { return false }
        return message == "state must be text, an object, or an array."
    }
    #expect(await mock.requests.isEmpty)
}

@Test(arguments: [
    (#"{}"#, "answers.question_0"),
    (#"{"question_0":{"type":"noul","noul":0.5}}"#, "answers.question_0"),
    (#"{"question_0":{"type":"future"}}"#, "answers.question_0"),
    (#"{"question_0":{"type":"choice","choice":"unknown","confidence":1,"probabilities":{"friendly":1}}}"#, "answers.question_0.choice"),
    (#"{"question_0":{"type":"choice","choice":"friendly","confidence":1,"probabilities":{"unknown":1}}}"#, "answers.question_0.probabilities.unknown"),
    (#"{"question_0":{"type":"choice","choice":"friendly","confidence":1}}"#, "answers.question_0.probabilities"),
])
func builderChoiceValidationRetainsContext(answers: String, expectedPath: String) async throws {
    let json = "{\"model\":\"m\",\"usage\":{},\"answers\":\(answers)}"
    let mock = MockTransport { _, _ in response(json) }
    do {
        _ = try await client(mock).systemOne(state: "s") { Choice<Tone>() }
        Issue.record("Expected response validation failure")
    } catch TypeSafeError.responseValidation(let api, let fieldPath) {
        #expect(fieldPath == expectedPath)
        #expect(api.status == 200)
        #expect(api.requestID == "req_123")
        #expect(api.body == (try JSONDecoder().decode(JSONValue.self, from: Data(json.utf8))))
    }
}

@Test(arguments: ["question_1", "question_2"])
func builderValidatesEveryAnswer(name: String) async throws {
    let json = try JSONDecoder().decode(JSONValue.self, from: Data(builderFixture.utf8))
    guard case .object(var root) = json, case .object(var answers) = root["answers"] else {
        Issue.record("Expected fixture objects")
        return
    }
    answers[name] = ["type": "choice", "choice": "friendly", "confidence": 1, "probabilities": ["friendly": 1]]
    root["answers"] = .object(answers)
    let data = try JSONEncoder().encode(root)
    let mock = MockTransport { _, _ in RawHTTPResponse(status: 200, body: data) }
    do {
        _ = try await client(mock).systemOne(state: "s") {
            Choice<Tone>()
            Noul()
            Score(criteria: ["only"])
        }
        Issue.record("Expected response validation failure")
    } catch TypeSafeError.responseValidation(_, let fieldPath) {
        #expect(fieldPath == "answers.\(name)")
    }
}

@Test func builderUsesSharedRetryAndAPIErrors() async throws {
    let mock = MockTransport { _, attempt in
        attempt == 1 ? response("busy", status: 503) : response(builderFixture)
    }
    let result = try await client(mock).systemOne(
        state: "s", options: .init(retry: RetryPolicy(maxRetries: 1, backoffInitial: 0, backoffMax: 0))
    ) { Choice<Tone>() }
    #expect(result.choice == .friendly)
    #expect(await mock.requests.count == 2)
    #expect(await mock.requests.last?.headers["x-typesafe-retry-count"] == "1")
    let failing = MockTransport { _, _ in response("bad request", status: 400) }
    do {
        _ = try await client(failing).systemOne(state: "s") { Noul() }
        Issue.record("Expected API error")
    } catch TypeSafeError.api(let error) {
        #expect(error.status == 400)
        #expect(error.requestID == "req_123")
    }
}

private final class LocalInstructions {
    var value = "Tone?"
}

@Test @MainActor func builderCanCaptureCallerIsolatedState() async throws {
    let instructions = LocalInstructions()
    var evaluations = 0
    func prompt() -> JSONValue {
        evaluations += 1
        return .string(instructions.value)
    }
    let mock = MockTransport { _, _ in response(builderFixture) }
    let answer = try await client(mock).systemOne(state: "s") {
        let instructions = prompt()
        Choice<Tone>(instructions)
    }
    #expect(answer.choice == .friendly)
    #expect(instructions.value == "Tone?")
    #expect(evaluations == 1)
}

private enum BuilderFailure: Error { case invalidInstructions }

@Test func builderPropagatesConstructionErrorsBeforeSending() async throws {
    func instructions() throws -> JSONValue { throw BuilderFailure.invalidInstructions }
    let mock = MockTransport()
    await #expect(throws: BuilderFailure.invalidInstructions) {
        _ = try await client(mock).systemOne(state: "s") {
            Noul(try instructions())
        }
    }
    #expect(await mock.requests.isEmpty)
}

private struct SpamProbability: TypedQuestion {
    var question: Question { .noul(instructions: "Spam?") }
    func decodeAnswer(from response: SystemOneResponse, named name: String) throws -> Double {
        try response.noul(named: name).noul
    }
}

@Test func builderSupportsCustomTypedQuestions() async throws {
    let json = #"{"model":"m","usage":{},"answers":{"question_0":{"type":"noul","noul":0.75}}}"#
    let mock = MockTransport { _, _ in response(json) }
    let probability: Double = try await client(mock).systemOne(state: "s") { SpamProbability() }
    #expect(probability == 0.75)
}
