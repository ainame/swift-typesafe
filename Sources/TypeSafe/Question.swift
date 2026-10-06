import Foundation

/// Dynamic questions. Omitted optional arguments are not sent; use `.raw` for explicit nulls.
public enum Question: Sendable, Equatable, Encodable {
    /// Dictionary criteria have no ordering guarantee; use `orderedCriteria:` when order matters.
    case noul(instructions: JSONValue? = nil, criteria: [String: JSONValue]? = nil)
    /// Dictionary criteria have no ordering guarantee; use `orderedCriteria:` when order matters.
    case choice(instructions: JSONValue? = nil, criteria: [String: JSONValue])
    case orderedNoul(instructions: JSONValue? = nil, criteria: OrderedCriteria)
    case orderedChoice(instructions: JSONValue? = nil, criteria: OrderedCriteria)
    case score(instructions: JSONValue? = nil, criteria: [JSONValue])
    /// Forward-compatible question object; unknown nonempty type tags pass through to the API.
    case raw([String: JSONValue])

    /// Dictionary criteria have no ordering guarantee. Use this overload for explicit order.
    public static func choice(instructions: JSONValue? = nil, orderedCriteria: OrderedCriteria) -> Self {
        .orderedChoice(instructions: instructions, criteria: orderedCriteria)
    }

    /// Sends criteria in their insertion order.
    public static func noul(instructions: JSONValue? = nil, orderedCriteria: OrderedCriteria) -> Self {
        .orderedNoul(instructions: instructions, criteria: orderedCriteria)
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
            if let criteria { result["criteria"] = .object(criteria) }
        case .choice(let value, let criteria):
            instructions = value
            result = ["type": "choice", "criteria": .object(criteria)]
        case .orderedNoul(let value, let criteria):
            instructions = value
            result = ["type": "noul", "criteria": .object(criteria.dictionary)]
        case .orderedChoice(let value, let criteria):
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
        case .orderedChoice(_, let criteria), .orderedNoul(_, let criteria):
            fields["criteria"] = .orderedObject(criteria)
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
