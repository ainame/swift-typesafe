import Foundation

/// Dynamic questions. Omitted optional arguments are not sent; use `.raw` for explicit nulls.
public enum Question: Sendable, Equatable, Encodable {
    case noul(instructions: JSONValue? = nil, criteria: Criteria? = nil)
    case choice(instructions: JSONValue? = nil, criteria: Criteria)
    case score(instructions: JSONValue? = nil, criteria: [JSONValue])
    /// Forward-compatible question object; unknown nonempty type tags pass through to the API.
    case raw([String: JSONValue])

    /// Compatibility for dictionary variables. Keys are sorted because their insertion order is unavailable.
    // The generic fallback keeps Swift from preferring Dictionary for an untyped literal.
    @_disfavoredOverload
    public static func choice<Descriptions: Collection>(
        instructions: JSONValue? = nil, criteria: Descriptions
    ) -> Self where Descriptions.Element == (key: String, value: JSONValue) {
        let dictionary = Dictionary(criteria.map { ($0.key, $0.value) }, uniquingKeysWith: { _, last in last })
        return .choice(instructions: instructions, criteria: Criteria(dictionary: dictionary))
    }

    /// Compatibility for optional dictionary variables, with sorted keys.
    @_disfavoredOverload
    public static func noul<Descriptions: Collection>(
        instructions: JSONValue? = nil, criteria: Descriptions?
    ) -> Self where Descriptions.Element == (key: String, value: JSONValue) {
        let ordered = criteria.map { entries in
            Criteria(dictionary: Dictionary(entries.map { ($0.key, $0.value) }, uniquingKeysWith: { _, last in last }))
        }
        return .noul(instructions: instructions, criteria: ordered)
    }

    public func encode(to encoder: any Encoder) throws { try payload.encode(to: encoder) }

    var payload: [String: JSONValue] {
        var result: [String: JSONValue]
        let instructions: JSONValue?
        switch self {
        case .raw(let value): return value
        case .noul(let value, let criteria):
            instructions = value
            result = ["type": "noul"]
            if let criteria { result["criteria"] = .object(criteria.dictionary) }
        case .choice(let value, let criteria):
            instructions = value
            result = ["type": "choice", "criteria": .object(criteria.dictionary)]
        case .score(let value, let criteria):
            instructions = value
            result = ["type": "score", "criteria": .array(criteria)]
        }
        if let instructions { result["instructions"] = instructions }
        return result
    }

    var wirePayload: RequestJSON {
        var fields = payload.mapValues { RequestJSON.value($0) }
        switch self {
        case .choice(_, let criteria):
            fields["criteria"] = .orderedObject(criteria)
        case .noul(_, let criteria):
            if let criteria { fields["criteria"] = .orderedObject(criteria) }
        default: break
        }
        return .object(fields)
    }

    func validate(name: String) throws {
        let body = payload
        guard let type = body["type"]?.stringValue, !type.isEmpty else {
            throw TypeSafeError.configuration("Question '\(name)' requires a nonempty string type.")
        }
        if type == "choice" || type == "score" {
            guard let criteria = body["criteria"] else {
                throw TypeSafeError.configuration("Question '\(name)' requires criteria.")
            }
            if type == "score" {
                let empty: Bool
                switch criteria {
                case .array(let values): empty = values.isEmpty
                case .object(let values): empty = values.isEmpty
                case .string(let value): empty = value.isEmpty
                case .null: empty = true
                default: empty = false
                }
                if empty { throw TypeSafeError.configuration("Score question '\(name)' requires at least one criterion.") }
            }
        }
    }
}
