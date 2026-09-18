import Foundation

public struct NoulAnswer: Codable, Sendable, Equatable {
    public let noul: Double
    public init(noul: Double) { self.noul = noul }
}

public struct ChoiceAnswer<Label: Hashable & Sendable>: Sendable, Equatable {
    public let choice: Label
    public let confidence: Double
    public let probabilities: [Label: Double]
    public init(choice: Label, confidence: Double, probabilities: [Label: Double]) {
        self.choice = choice; self.confidence = confidence; self.probabilities = probabilities
    }
}

extension ChoiceAnswer: Codable where Label: Codable {}

public struct ScoreAnswer: Codable, Sendable, Equatable {
    public let score: Double
    public let confidence: Double
    public let legend: [Int: JSONValue]
    public let probabilities: [Int: Double]
    public init(score: Double, confidence: Double, legend: [Int: JSONValue], probabilities: [Int: Double]) {
        self.score = score; self.confidence = confidence; self.legend = legend; self.probabilities = probabilities
    }
    enum CodingKeys: CodingKey { case score, confidence, legend, probabilities }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        score = try c.decode(Double.self, forKey: .score)
        confidence = try c.decode(Double.self, forKey: .confidence)
        legend = try c.decode([Int: JSONValue].self, forKey: .legend)
        probabilities = try c.decode([Int: Double].self, forKey: .probabilities)
        for (key, value) in legend where !value.isContent {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath + [CodingKeys.legend, DynamicKey(String(key))], debugDescription: "Expected text, an object, or an array."))
        }
    }
}

public enum Answer: Sendable, Equatable, Codable {
    case noul(NoulAnswer), choice(ChoiceAnswer<String>), score(ScoreAnswer)
    enum CodingKeys: CodingKey { case type }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        switch try c.decode(String.self, forKey: .type) {
        case "noul": self = .noul(try NoulAnswer(from: decoder))
        case "choice": self = .choice(try ChoiceAnswer<String>(from: decoder))
        case "score": self = .score(try ScoreAnswer(from: decoder))
        default: throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "Unknown answer type.")
        }
    }
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .noul(let value): try c.encode("noul", forKey: .type); try value.encode(to: encoder)
        case .choice(let value): try c.encode("choice", forKey: .type); try value.encode(to: encoder)
        case .score(let value): try c.encode("score", forKey: .type); try value.encode(to: encoder)
        }
    }
}

public struct Usage: Codable, Sendable, Equatable {
    public let inputTokens: Int?
    public let outputTokens: Int?
    enum CodingKeys: String, CodingKey { case inputTokens = "input_tokens", outputTokens = "output_tokens" }
}

public struct ModelCard: Codable, Sendable, Equatable {
    public let name: String
    public let description: String
    public let releaseDate: String
    enum CodingKeys: String, CodingKey { case name, description, releaseDate = "release_date" }
}

/// Buffered HTTP response. Metadata is excluded when SDK responses are encoded as JSON.
public struct RawHTTPResponse: Sendable, Equatable {
    public let status: Int
    public let headers: [String: String]
    public let body: Data
    public init(status: Int, headers: [String: String] = [:], body: Data = Data()) {
        self.status = status; self.headers = headers; self.body = body
    }
    public var requestID: String? { headers.first { $0.key.lowercased() == "x-typesafe-request-id" }?.value }
}

public struct SystemOneResponse: Codable, Sendable {
    public let model: String
    public let usage: Usage
    public let answers: [String: Answer]
    public internal(set) var rawHTTPResponse: RawHTTPResponse? = nil
    public var requestID: String? { rawHTTPResponse?.requestID }
    public var nouls: [String: NoulAnswer] { answers.compactMapValues { if case .noul(let a) = $0 { a } else { nil } } }
    public var choices: [String: ChoiceAnswer<String>] { answers.compactMapValues { if case .choice(let a) = $0 { a } else { nil } } }
    public var scores: [String: ScoreAnswer] { answers.compactMapValues { if case .score(let a) = $0 { a } else { nil } } }
    enum CodingKeys: CodingKey { case model, usage, answers }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        model = try c.decode(String.self, forKey: .model)
        usage = try c.decode(Usage.self, forKey: .usage)
        let fields = try c.nestedContainer(keyedBy: DynamicKey.self, forKey: .answers)
        var result: [String: Answer] = [:]
        for key in fields.allKeys {
            let tag = try fields.nestedContainer(keyedBy: Answer.CodingKeys.self, forKey: key)
            let type = try tag.decode(String.self, forKey: .type)
            if ["noul", "choice", "score"].contains(type) { result[key.stringValue] = try fields.decode(Answer.self, forKey: key) }
        }
        answers = result
    }

    public func noul(named name: String) throws -> NoulAnswer {
        guard case .noul(let answer) = answers[name] else { throw invalidAnswer(name) }
        return answer
    }
    public func score(named name: String) throws -> ScoreAnswer {
        guard case .score(let answer) = answers[name] else { throw invalidAnswer(name) }
        return answer
    }
    public func choice<Label: RawRepresentable & Hashable & Sendable>(named name: String, as: Label.Type) throws -> ChoiceAnswer<Label> where Label.RawValue == String {
        guard case .choice(let answer) = answers[name] else { throw invalidAnswer(name) }
        guard let choice = Label(rawValue: answer.choice) else { throw invalidAnswer(name, suffix: ".choice") }
        var probabilities: [Label: Double] = [:]
        for (key, value) in answer.probabilities {
            guard let label = Label(rawValue: key) else { throw invalidAnswer(name, suffix: ".probabilities.\(key)") }
            probabilities[label] = value
        }
        return ChoiceAnswer(choice: choice, confidence: answer.confidence, probabilities: probabilities)
    }
    private func invalidAnswer(_ name: String, suffix: String = "") -> TypeSafeError {
        let path = "answers.\(name)\(suffix)"
        let raw = rawHTTPResponse ?? RawHTTPResponse(status: 200)
        return .responseValidation(APIError(status: raw.status, body: decodeBody(raw.body), headers: raw.headers,
                                           message: "Invalid response data at '\(path)'."), fieldPath: path)
    }
}

public struct ListModelsResponse: Codable, Sendable {
    public let models: [ModelCard]
    public internal(set) var rawHTTPResponse: RawHTTPResponse? = nil
    public var requestID: String? { rawHTTPResponse?.requestID }
    enum CodingKeys: CodingKey { case models }
}

struct DynamicKey: CodingKey {
    let stringValue: String
    var intValue: Int? { Int(stringValue) }
    init(_ value: String) { stringValue = value }
    init?(stringValue: String) { self.init(stringValue) }
    init?(intValue: Int) { self.init(String(intValue)) }
}

func decodeBody(_ data: Data) -> JSONValue {
    if data.isEmpty { return .null }
    return (try? JSONDecoder().decode(JSONValue.self, from: data)) ?? .string(String(decoding: data, as: UTF8.self))
}

func decodingPath(_ error: DecodingError) -> String {
    let path: [any CodingKey]
    switch error {
    case .keyNotFound(let key, let context): path = context.codingPath + [key]
    case .dataCorrupted(let context), .typeMismatch(_, let context), .valueNotFound(_, let context): path = context.codingPath
    @unknown default: return ""
    }
    return path.reduce("") { result, key in
        // JSONDecoder uses "Index N" coding keys for array elements.
        if key.stringValue.hasPrefix("Index "), let index = key.intValue { return result + "[\(index)]" }
        return result + (result.isEmpty ? "" : ".") + key.stringValue
    }
}
