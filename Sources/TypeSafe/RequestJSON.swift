import Foundation

/// Foundation's keyed JSON encoding does not preserve insertion order, even for ordered inputs.
/// Assemble object boundaries here and let JSONEncoder escape keys and encode JSON values.
indirect enum RequestJSON {
    case value(JSONValue)
    case object([String: RequestJSON])
    case orderedObject(Criteria)

    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        switch self {
        case .value(let value): return try encoder.encode(value)
        case .object(let fields):
            return try encodeObject(fields.keys.sorted().map { ($0, fields[$0]!) }, encoder: encoder)
        case .orderedObject(let criteria):
            return try encodeObject(criteria.entries.map { ($0.key, .value($0.value)) }, encoder: encoder)
        }
    }

    private func encodeObject(_ entries: [(String, RequestJSON)], encoder: JSONEncoder) throws -> Data {
        var data = Data("{".utf8)
        for (index, entry) in entries.enumerated() {
            if index > 0 { data.append(contentsOf: ",".utf8) }
            data.append(try encoder.encode(entry.0))
            data.append(contentsOf: ":".utf8)
            data.append(try entry.1.encoded())
        }
        data.append(contentsOf: "}".utf8)
        return data
    }
}
