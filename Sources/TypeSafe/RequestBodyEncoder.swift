import Foundation

/// Writes the request directly into one buffer. Foundation handles JSON escaping and values;
/// object boundaries are written here because keyed JSON encoding does not preserve criteria order.
struct RequestBodyEncoder {
    private let encoder = JSONEncoder()
    private var data = Data()

    mutating func encode(
        state: JSONValue, model: String, questions: [String: Question], extraBody: [String: JSONValue]
    ) throws -> Data {
        var fields: [String: JSONValue] = ["state": state, "model": .string(model)]
        fields.merge(extraBody, uniquingKeysWith: { _, last in last })
        let keys = Set(fields.keys).union(["questions"]).sorted()
        try writeObject(keys, key: { $0 }) { writer, key in
            if let value = fields[key] {
                try writer.write(value)
            } else {
                try writer.writeObject(questions.keys.sorted(), key: { $0 }) { writer, name in
                    try writer.writeQuestion(questions[name]!)
                }
            }
        }
        return data
    }

    private mutating func writeQuestion(_ question: Question) throws {
        switch question {
        case .raw(let fields): try write(fields)
        case .choice(let instructions, let criteria):
            try writeQuestion(type: "choice", instructions: instructions) { writer in
                try writer.writeCriteria(criteria)
            }
        case .noul(let instructions, let criteria):
            try writeQuestion(type: "noul", instructions: instructions, hasCriteria: criteria != nil) { writer in
                if let criteria { try writer.writeCriteria(criteria) }
            }
        case .score(let instructions, let criteria):
            try writeQuestion(type: "score", instructions: instructions) { writer in
                try writer.write(criteria)
            }
        }
    }

    private mutating func writeQuestion(
        type: String, instructions: JSONValue?, hasCriteria: Bool = true,
        criteria: (inout Self) throws -> Void
    ) throws {
        var keys: [String] = []
        if hasCriteria { keys.append("criteria") }
        if instructions != nil { keys.append("instructions") }
        keys.append("type")
        try writeObject(keys, key: { $0 }) { writer, key in
            switch key {
            case "criteria": try criteria(&writer)
            case "instructions": try writer.write(instructions!)
            default: try writer.write(type)
            }
        }
    }

    private mutating func writeCriteria(_ criteria: Criteria) throws {
        try writeObject(criteria.entries, key: { $0.key }) { writer, entry in
            try writer.write(entry.value)
        }
    }

    private mutating func writeObject<Entries: Sequence>(
        _ entries: Entries, key: (Entries.Element) -> String,
        value: (inout Self, Entries.Element) throws -> Void
    ) throws {
        data.append(contentsOf: "{".utf8)
        var first = true
        for entry in entries {
            if !first { data.append(contentsOf: ",".utf8) }
            first = false
            try write(key(entry))
            data.append(contentsOf: ":".utf8)
            try value(&self, entry)
        }
        data.append(contentsOf: "}".utf8)
    }

    private mutating func write<Value: Encodable>(_ value: Value) throws {
        data.append(try encoder.encode(value))
    }
}
