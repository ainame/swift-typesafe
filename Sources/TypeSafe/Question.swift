import Foundation

/// Dynamic questions. Omitted optional arguments are not sent; use `.raw` for explicit nulls.
public enum Question: Sendable, Equatable, Encodable {
    case noul(instructions: JSONValue? = nil, criteria: [String: JSONValue]? = nil)
    case choice(instructions: JSONValue? = nil, criteria: [String: JSONValue])
    case score(instructions: JSONValue? = nil, criteria: [JSONValue])
    /// Forward-compatible question object; unknown nonempty type tags pass through to the API.
    case raw([String: JSONValue])

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
        case .score(let value, let criteria):
            instructions = value
            result = ["type": "score", "criteria": .array(criteria)]
        }
        if let instructions { result["instructions"] = instructions }
        return result
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
