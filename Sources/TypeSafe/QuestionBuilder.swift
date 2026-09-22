/// A typed question backed by the dynamic request and response implementation.
public protocol TypedQuestion: Sendable {
    associatedtype Answer: Sendable
    var question: Question { get }
    func decodeAnswer(from response: SystemOneResponse, named name: String) throws -> Answer
}

/// An enum-valued choice. Omitted criteria include every case with a null description.
public struct Choice<Label: CaseIterable & RawRepresentable & Hashable & Sendable>: TypedQuestion where Label.RawValue == String {
    public let question: Question

    public init(_ instructions: JSONValue? = nil, criteria: [String: JSONValue]? = nil) {
        question = .choice(instructions: instructions, criteria: choiceCriteria(for: Label.self, descriptions: criteria))
    }

    public func decodeAnswer(from response: SystemOneResponse, named name: String) throws -> ChoiceAnswer<Label> {
        try response.choice(named: name, as: Label.self)
    }
}

/// A yes probability, with optional descriptions for the "true" and "false" criteria.
public struct Noul: TypedQuestion {
    public let question: Question

    public init(_ instructions: JSONValue? = nil, criteria: [String: JSONValue]? = nil) {
        question = .noul(instructions: instructions, criteria: criteria)
    }

    public func decodeAnswer(from response: SystemOneResponse, named name: String) throws -> NoulAnswer {
        try response.noul(named: name)
    }
}

/// An expected score over an ordered rubric. The returned score may be fractional.
public struct Score: TypedQuestion {
    public let question: Question

    public init(_ instructions: JSONValue? = nil, criteria: [JSONValue]) {
        question = .score(instructions: instructions, criteria: criteria)
    }

    public func decodeAnswer(from response: SystemOneResponse, named name: String) throws -> ScoreAnswer {
        try response.score(named: name)
    }
}

/// The ordered questions and typed answer projection produced by `QuestionBuilder`.
///
/// `Answers` is a flat tuple, or the answer type itself for a single question.
public struct Questions<Answers: Sendable>: Sendable {
    let questions: [String: Question]
    let decodeAnswers: @Sendable (SystemOneResponse) throws -> Answers
}

/// Builds a fixed sequence of typed questions without a fixed arity limit.
///
/// Runtime-sized loops and conditional question insertion are intentionally unsupported:
/// the answer tuple's shape is determined at compile time.
@resultBuilder
public enum QuestionBuilder {
    public static func buildBlock<each Q: TypedQuestion>(_ questions: repeat each Q) -> Questions<(repeat (each Q).Answer)> {
        let elements = (repeat each questions)
        var wireQuestions: [String: Question] = [:]
        var index = 0
        for question in repeat each elements {
            wireQuestions[name(at: index)] = question.question
            index += 1
        }
        return Questions(questions: wireQuestions) { response in
            var index = 0
            func decode<T: TypedQuestion>(_ question: T) throws -> T.Answer {
                defer { index += 1 }
                return try question.decodeAnswer(from: response, named: name(at: index))
            }
            return (repeat try decode(each elements))
        }
    }

    private static func name(at index: Int) -> String { "question_\(index)" }
}

extension TypeSafeClient {
    /// Returns typed answers and response metadata, matching the schema overload.
    ///
    /// `answers` contains a flat tuple in declaration order, or a single answer for one question.
    ///
    /// Wire keys are `question_0`, `question_1`, and so on. Empty builders throw a
    /// configuration error before sending a request. Use the dynamic overload
    /// when runtime-sized question collections are needed.
    public nonisolated(nonsending) func systemOne<Answers: Sendable>(
        state: JSONValue, model: String? = nil,
        extraBody: [String: JSONValue] = [:], options: RequestOptions = RequestOptions(),
        @QuestionBuilder questions: () throws -> Questions<Answers>
    ) async throws -> TypedSystemOneResponse<Answers> {
        let questions = try questions()
        let response = try await systemOne(
            state: state, questions: questions.questions, model: model, extraBody: extraBody, options: options
        )
        return TypedSystemOneResponse(answers: try questions.decodeAnswers(response), response: response)
    }
}
