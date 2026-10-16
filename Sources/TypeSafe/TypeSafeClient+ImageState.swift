import Foundation

extension TypeSafeClient {
    /// Evaluates an image using the shared image upload path.
    public func systemOne(
        state: Image, questions: [String: Question], model: String? = nil,
        extraBody: [String: JSONValue] = [:], assets: [String: Image] = [:], options: RequestOptions = RequestOptions()
    ) async throws -> SystemOneResponse {
        try await systemOne(state: .image(state), questions: questions, model: model,
                            extraBody: extraBody, assets: assets, options: options)
    }

    /// Evaluates an image and decodes a caller-defined response.
    public func systemOne<Response: Decodable & Sendable>(
        state: Image, questions: [String: Question], model: String? = nil,
        extraBody: [String: JSONValue] = [:], assets: [String: Image] = [:], options: RequestOptions = RequestOptions(),
        responseModel: Response.Type
    ) async throws -> Response {
        try await systemOne(state: .image(state), questions: questions, model: model,
                            extraBody: extraBody, assets: assets, options: options, responseModel: responseModel)
    }

    /// Evaluates an image with a reusable question schema.
    public func systemOne<Schema: QuestionSet>(
        state: Image, questions: Schema.Type, model: String? = nil,
        extraBody: [String: JSONValue] = [:], assets: [String: Image] = [:], options: RequestOptions = RequestOptions()
    ) async throws -> TypedSystemOneResponse<Schema.Answers> {
        try await systemOne(state: .image(state), questions: questions, model: model,
                            extraBody: extraBody, assets: assets, options: options)
    }

    /// Evaluates an image with typed ad-hoc questions.
    public nonisolated(nonsending) func systemOne<Answers: Sendable>(
        state: Image, model: String? = nil,
        extraBody: [String: JSONValue] = [:], assets: [String: Image] = [:], options: RequestOptions = RequestOptions(),
        @QuestionBuilder questions: () throws -> Questions<Answers>
    ) async throws -> TypedSystemOneResponse<Answers> {
        try await systemOne(state: .image(state), model: model,
                            extraBody: extraBody, assets: assets, options: options, questions: questions)
    }
}
