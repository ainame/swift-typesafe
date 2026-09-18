import Foundation
import Testing
import TypeSafe

enum Tone: String, CaseIterable, Codable, Sendable { case friendly, hostile }

@QuestionSet
struct TicketQuestions {
    @Noul("Spam?") var spam: Double
    @Choice("Tone?") var tone: Tone
    @Score("Quality?", criteria: ["bad", "ok", "great"]) var quality: Double
}

@Test func macroGeneratesTypedAnswers() async throws {
    let mock = MockTransport()
    let result = try await client(mock).systemOne(state: "Hello", questions: TicketQuestions.self)
    let tone: Tone = result.answers.tone.choice
    #expect(tone == .friendly)
    #expect(result.answers.spam.noul == 0.98)
    #expect(result.answers.quality.score == 1.7)
    #expect(result.answers.tone.probabilities[.friendly] == 0.9)
    #expect(result.requestID == "req_123")
    let request = try #require(await mock.requests.first)
    let body = try JSONDecoder().decode(JSONValue.self, from: #require(request.body))
    #expect(body["questions"]?["tone"]?["criteria"] == ["friendly": nil, "hostile": nil])
}

@Test(arguments: ["unknown", "missing"])
func typedResponseRejectsInvalidChoices(kind: String) async throws {
    let json = kind == "unknown" ? resultFixture.replacingOccurrences(of: "friendly", with: "unknown") : #"{"model":"m","usage":{},"answers":{}}"#
    let mock = MockTransport { _, _ in response(json) }
    await #expect(throws: TypeSafeError.self) {
        _ = try await client(mock).systemOne(state: "Hello", questions: TicketQuestions.self)
    }
}

@QuestionSet
public struct PublicQuestions {
    @Noul("Enabled?", criteria: ["true": "yes", "false": "no"])
    var `default`: Double
}

@QuestionSet
struct DescribedChoices {
    @Choice("Tone?", criteria: ["friendly": "Welcoming", "hostile": nil])
    var tone: Tone
}

@Test func macroSupportsDescriptionsAndEscapedNames() async throws {
    #expect(PublicQuestions.questions["default"] == .noul(instructions: "Enabled?", criteria: ["true": "yes", "false": "no"]))
    #expect(DescribedChoices.questions["tone"] == .choice(instructions: "Tone?", criteria: ["friendly": "Welcoming", "hostile": nil]))
    let result = try await client().systemOne(state: "hi", questions: DescribedChoices.self)
    #expect(result.answers.tone.choice == .friendly)
}
