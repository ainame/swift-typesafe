import Foundation
import Testing
import TypeSafe

private enum Category: String, CaseIterable, Sendable { case billing, technical, other }

@QuestionSet
private struct OrderedQuestions {
    @Choice(criteria: ["other": "Fallback", "technical": "Help", "billing": "Payment"])
    var category: Category
    @Noul(orderedCriteria: ["true": "Yes", "false": "No"])
    var spam: Double
}

private let orderedFixture = #"{"model":"m","usage":{},"answers":{"category":{"type":"choice","choice":"billing","confidence":1,"probabilities":{"billing":1}},"spam":{"type":"noul","noul":0.2}}}"#

@Test(arguments: ["macro", "builder", "dynamic", "customResponse"])
func criteriaOrderReachesRequestBytes(api: String) async throws {
    let mock = MockTransport { _, _ in
        response(api == "builder" ? orderedFixture
            .replacingOccurrences(of: "\"category\":", with: "\"question_0\":")
            .replacingOccurrences(of: "\"spam\":", with: "\"question_1\":") : orderedFixture)
    }
    let c = try client(mock)
    switch api {
    case "macro": _ = try await c.systemOne(state: "s", questions: OrderedQuestions.self)
    case "builder":
        _ = try await c.systemOne(state: "s") {
            Choice<Category>(criteria: ["other": "Fallback", "technical": "Help", "billing": "Payment"])
            Noul(orderedCriteria: ["true": "Yes", "false": "No"])
        }
    default:
        let questions: [String: Question] = [
            "category": .choice(orderedCriteria: ["billing": "Payment", "technical": "Help", "other": "Fallback"]),
            "spam": .noul(orderedCriteria: ["true": "Yes", "false": "No"]),
        ]
        if api == "customResponse" {
            struct Custom: Decodable, Sendable { let model: String }
            _ = try await c.systemOne(state: "s", questions: questions, responseModel: Custom.self)
        } else {
            _ = try await c.systemOne(state: "s", questions: questions)
        }
    }
    let request = try #require(await mock.requests.first)
    let data = try #require(request.body)
    let text = String(decoding: data, as: UTF8.self)
    // Decoding into a Dictionary would discard the ordering this regression needs to check.
    #expect(text.contains(#""criteria":{"billing":"Payment","technical":"Help","other":"Fallback"}"#))
    #expect(text.contains(#""criteria":{"true":"Yes","false":"No"}"#))
    let json = try JSONDecoder().decode(JSONValue.self, from: data)
    let key = api == "builder" ? "question_0" : "category"
    #expect(json["questions"]?[key]?["criteria"] == ["billing": "Payment", "technical": "Help", "other": "Fallback"])
}

@Test func enumDefaultsAndDescriptionSubsetsKeepCaseOrder() async throws {
    let mock = MockTransport()
    _ = try await client(mock).systemOne(state: "s", questions: [
        "defaults": Choice<Category>().question,
        "subset": Choice<Category>(criteria: ["other": nil, "billing": "Payment"]).question,
        "extensions": Choice<Category>(criteria: ["zzz": nil, "aaa": nil, "other": nil]).question,
    ])
    let request = try #require(await mock.requests.first)
    let text = String(decoding: try #require(request.body), as: UTF8.self)
    #expect(text.contains(#""criteria":{"billing":null,"technical":null,"other":null}"#))
    #expect(text.contains(#""criteria":{"billing":"Payment","other":null}"#))
    #expect(text.contains(#""criteria":{"other":null,"aaa":null,"zzz":null}"#))
}

@Test func orderedCriteriaSupportsExplicitBuilderOrderAndEscapedJSON() async throws {
    let pairs: KeyValuePairs<String, JSONValue> = ["other": ["text": "Line\n\"quoted\""], "billing": nil]
    let criteria = OrderedCriteria(pairs)
    #expect(OrderedCriteria(pairs: pairs.map { ($0.key, $0.value) }) == criteria)
    let mock = MockTransport()
    _ = try await client(mock).systemOne(state: "s", questions: [
        "choice": Choice<Category>(orderedCriteria: criteria).question,
        "duplicate": .choice(orderedCriteria: ["other": "First", "billing": nil, "other": "Last"]),
        "escaped": .noul(orderedCriteria: ["a\"\n": "value\t", "false": nil]),
    ])
    let request = try #require(await mock.requests.first)
    let data = try #require(request.body)
    let text = String(decoding: data, as: UTF8.self)
    #expect(text.contains(#""criteria":{"other":{"text":"Line\n\"quoted\""},"billing":null}"#))
    #expect(text.contains(#""criteria":{"other":"Last","billing":null}"#))
    let json = try JSONDecoder().decode(JSONValue.self, from: data)
    #expect(json["questions"]?["escaped"]?["criteria"] == ["a\"\n": "value\t", "false": nil])
}

@Test func extraBodyStillReplacesOrderedQuestions() async throws {
    let mock = MockTransport()
    _ = try await client(mock).systemOne(state: "s", questions: ["choice": Choice<Category>().question],
        extraBody: ["questions": ["replacement": ["type": "noul"]]])
    let request = try #require(await mock.requests.first)
    let json = try JSONDecoder().decode(JSONValue.self, from: #require(request.body))
    #expect(json["questions"] == ["replacement": ["type": "noul"]])
}
