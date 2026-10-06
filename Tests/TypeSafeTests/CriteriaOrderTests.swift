import Foundation
import Testing
import TypeSafe

private enum Category: String, CaseIterable, Sendable { case billing, technical, other }

@QuestionSet
private struct OrderedQuestions {
    @Choice(criteria: ["other": "Fallback", "technical": "Help", "billing": "Payment"])
    var category: Category
    @Noul(criteria: ["true": "Yes", "false": "No"])
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
            Noul(criteria: ["true": "Yes", "false": "No"])
        }
    default:
        let questions: [String: Question] = [
            "category": .choice(criteria: ["other": "Fallback", "technical": "Help", "billing": "Payment"]),
            "spam": .noul(criteria: ["true": "Yes", "false": "No"]),
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
    #expect(text.contains(#""criteria":{"other":"Fallback","technical":"Help","billing":"Payment"}"#))
    #expect(text.contains(#""criteria":{"true":"Yes","false":"No"}"#))
    let json = try JSONDecoder().decode(JSONValue.self, from: data)
    let key = api == "builder" ? "question_0" : "category"
    #expect(json["questions"]?[key]?["criteria"] == ["billing": "Payment", "technical": "Help", "other": "Fallback"])
}

@Test func enumDefaultsAndExplicitSubsetsPreserveTheirOrder() async throws {
    let mock = MockTransport()
    _ = try await client(mock).systemOne(state: "s", questions: [
        "defaults": Choice<Category>().question,
        "subset": Choice<Category>(criteria: ["other": nil, "billing": "Payment"]).question,
        "extensions": Choice<Category>(criteria: ["zzz": nil, "aaa": nil, "other": nil]).question,
    ])
    let request = try #require(await mock.requests.first)
    let text = String(decoding: try #require(request.body), as: UTF8.self)
    #expect(text.contains(#""criteria":{"billing":null,"technical":null,"other":null}"#))
    #expect(text.contains(#""criteria":{"other":null,"billing":"Payment"}"#))
    #expect(text.contains(#""criteria":{"zzz":null,"aaa":null,"other":null}"#))
}

@Test func orderedCriteriaSupportsExplicitBuilderOrderAndEscapedJSON() async throws {
    let pairs: KeyValuePairs<String, JSONValue> = ["other": ["text": "Line\n\"quoted\""], "billing": nil]
    let criteria = OrderedCriteria(pairs)
    #expect(OrderedCriteria(pairs: pairs.map { ($0.key, $0.value) }) == criteria)
    let mock = MockTransport()
    _ = try await client(mock).systemOne(state: "s", questions: [
        "choice": Choice<Category>(criteria: criteria).question,
        "duplicate": .choice(criteria: ["other": "First", "billing": nil, "other": "Last"]),
        "escaped": .noul(criteria: ["a\"\n": "value\t", "false": nil]),
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

private let dictionaryDescriptions: [String: JSONValue] = ["other": nil, "billing": "Payment"]
private let dictionaryNoul: [String: JSONValue]? = ["true": "Yes", "false": "No"]

@QuestionSet
private struct DictionaryQuestions {
    @Choice(criteria: dictionaryDescriptions) var category: Category
    @Noul(criteria: dictionaryNoul) var spam: Double
}

@Test(arguments: ["dynamic", "builder", "macro"])
func dictionaryVariablesRemainSupportedWithStableOrder(api: String) async throws {
    let mock = MockTransport { _, _ in response(orderedFixture) }
    let c = try client(mock)
    switch api {
    case "macro": _ = try await c.systemOne(state: "s", questions: DictionaryQuestions.self)
    default:
        let choice = api == "builder" ? Choice<Category>(criteria: dictionaryDescriptions).question
            : Question.choice(criteria: dictionaryDescriptions)
        let noul = api == "builder" ? Noul(criteria: dictionaryNoul).question
            : Question.noul(criteria: dictionaryNoul)
        _ = try await c.systemOne(state: "s", questions: ["category": choice, "spam": noul])
    }
    let request = try #require(await mock.requests.first)
    let text = String(decoding: try #require(request.body), as: UTF8.self)
    #expect(text.contains(#""criteria":{"billing":"Payment","other":null}"#))
    #expect(text.contains(#""criteria":{"false":"No","true":"Yes"}"#))
}

@Test func omittedNullAndEmptyCriteriaRemainDistinct() async throws {
    let nilDictionary: [String: JSONValue]? = nil
    let mock = MockTransport()
    _ = try await client(mock).systemOne(state: "s", questions: [
        "omitted": .noul(), "nil": .noul(criteria: nil), "dictionaryNil": .noul(criteria: nilDictionary),
        "empty": .noul(criteria: [:]), "emptyChoice": .choice(criteria: [:]),
    ])
    let request = try #require(await mock.requests.first)
    let json = try JSONDecoder().decode(JSONValue.self, from: #require(request.body))
    for name in ["omitted", "nil", "dictionaryNil"] {
        #expect(json["questions"]?[name]?["criteria"] == nil)
    }
    #expect(json["questions"]?["empty"]?["criteria"] == .object([:]))
    #expect(json["questions"]?["emptyChoice"]?["criteria"] == .object([:]))
}

private let optionalOrderedNoul: OrderedCriteria? = ["true": "Yes", "false": "No"]

@QuestionSet
private struct OptionalOrderedQuestions {
    @Noul(criteria: optionalOrderedNoul) var spam: Double
}

@Test func macroAcceptsOptionalOrderedCriteria() async throws {
    let mock = MockTransport { _, _ in response(orderedFixture) }
    _ = try await client(mock).systemOne(state: "s", questions: OptionalOrderedQuestions.self)
    let request = try #require(await mock.requests.first)
    let text = String(decoding: try #require(request.body), as: UTF8.self)
    #expect(text.contains(#""criteria":{"true":"Yes","false":"No"}"#))
}
