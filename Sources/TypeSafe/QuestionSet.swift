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

/// Marks an enum choice. Omitted criteria follow `allCases`; supplied criteria preserve insertion order.
@attached(peer)
public macro Choice(_ instructions: JSONValue? = nil, criteria: Criteria? = nil) = #externalMacro(module: "TypeSafeMacros", type: "QuestionMarkerMacro")

/// Compatibility for dictionary variables; known keys follow enum order and extra keys are sorted.
@attached(peer)
public macro Choice(_ instructions: JSONValue? = nil, criteria: [String: JSONValue]?) = #externalMacro(module: "TypeSafeMacros", type: "QuestionMarkerMacro")

/// Marks a yes probability. Supplied criteria preserve insertion order.
@attached(peer)
public macro Noul(_ instructions: JSONValue? = nil, criteria: Criteria? = nil) = #externalMacro(module: "TypeSafeMacros", type: "QuestionMarkerMacro")

/// Compatibility for dictionary variables, which use sorted keys.
@attached(peer)
public macro Noul(_ instructions: JSONValue? = nil, criteria: [String: JSONValue]?) = #externalMacro(module: "TypeSafeMacros", type: "QuestionMarkerMacro")

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
public func choiceCriteria<Label: CaseIterable & RawRepresentable>(for type: Label.Type, descriptions: [String: JSONValue]? = nil) -> [String: JSONValue] where Label.RawValue == String {
    descriptions ?? Dictionary(Label.allCases.map { ($0.rawValue, JSONValue.null) }, uniquingKeysWith: { _, last in last })
}

/// Used by enum-backed questions. Explicit criteria preserve insertion order;
/// omitted criteria include every enum case in `allCases` order with null descriptions.
public func makeChoiceCriteria<Label: CaseIterable & RawRepresentable>(
    for type: Label.Type, descriptions: Criteria? = nil
) -> Criteria where Label.RawValue == String {
    descriptions ?? Criteria(pairs: Label.allCases.map { ($0.rawValue, .null) })
}

/// Compatibility for dictionary variables, preserving their subset in enum order.
@_disfavoredOverload
public func makeChoiceCriteria<Label: CaseIterable & RawRepresentable>(
    for type: Label.Type, descriptions: [String: JSONValue]?
) -> Criteria where Label.RawValue == String {
    let labels = Label.allCases.map { $0.rawValue }
    let descriptions = choiceCriteria(for: type, descriptions: descriptions)
    let known = Set(labels)
    let keys = labels.filter { descriptions[$0] != nil } + descriptions.keys.filter { !known.contains($0) }.sorted()
    return Criteria(pairs: keys.map { ($0, descriptions[$0]!) })
}
