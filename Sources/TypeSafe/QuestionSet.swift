/// A static question schema. Prefer `@QuestionSet` to implementing this protocol manually.
public protocol QuestionSet {
    associatedtype Answers: Sendable
    static var questions: [String: Question] { get }
    static func decodeAnswers(from response: SystemOneResponse) throws -> Answers
}

/// Generates the wire questions, an `Answers` type, and validated response mapping.
@attached(member, names: named(questions), named(Answers), named(decodeAnswers))
@attached(extension, conformances: QuestionSet)
public macro QuestionSet() = #externalMacro(module: "TypeSafeMacros", type: "QuestionSetMacro")

/// Marks a String-backed, CaseIterable choice enum property. Omitted criteria include all enum cases.
@attached(peer)
public macro Choice(_ instructions: JSONValue? = nil, criteria: [String: JSONValue]? = nil) = #externalMacro(module: "TypeSafeMacros", type: "QuestionMarkerMacro")

/// Marks a Double property representing a yes probability.
@attached(peer)
public macro Noul(_ instructions: JSONValue? = nil, criteria: [String: JSONValue]? = nil) = #externalMacro(module: "TypeSafeMacros", type: "QuestionMarkerMacro")

/// Marks a Double property representing an expected score (which may be fractional).
@attached(peer)
public macro Score(_ instructions: JSONValue? = nil, criteria: [JSONValue]) = #externalMacro(module: "TypeSafeMacros", type: "QuestionMarkerMacro")

public struct TypedSystemOneResponse<Answers: Sendable>: Sendable {
    public let answers: Answers
    public let response: SystemOneResponse
    public var model: String { response.model }
    public var usage: Usage { response.usage }
    public var requestID: String? { response.requestID }
    public var rawHTTPResponse: RawHTTPResponse? { response.rawHTTPResponse }
}

extension TypeSafeClient {
    public func systemOne<Schema: QuestionSet>(
        state: JSONValue, questions: Schema.Type, model: String? = nil,
        extraBody: [String: JSONValue] = [:], options: RequestOptions = RequestOptions()
    ) async throws -> TypedSystemOneResponse<Schema.Answers> {
        let response = try await systemOne(state: state, questions: Schema.questions, model: model, extraBody: extraBody, options: options)
        return TypedSystemOneResponse(answers: try Schema.decodeAnswers(from: response), response: response)
    }
}

/// Used by generated code to construct criteria without exposing type erasure.
public func choiceCriteria<Label: CaseIterable & RawRepresentable>(for type: Label.Type) -> [String: JSONValue] where Label.RawValue == String {
    Dictionary(Label.allCases.map { ($0.rawValue, JSONValue.null) }, uniquingKeysWith: { _, last in last })
}
