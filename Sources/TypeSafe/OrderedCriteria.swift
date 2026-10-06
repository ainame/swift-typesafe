/// Criteria whose JSON keys are sent in insertion order by `TypeSafeClient`.
/// Dictionary literals preserve their written order; runtime entries can use `KeyValuePairs`.
/// Repeated keys keep their first position and their last description.
public struct OrderedCriteria: Sendable, Equatable, ExpressibleByDictionaryLiteral {
    struct Entry: Sendable, Equatable {
        let key: String
        var value: JSONValue
    }
    var entries: [Entry]

    public init(_ pairs: KeyValuePairs<String, JSONValue>) {
        self.init(entries: pairs.map { Entry(key: $0.key, value: $0.value) })
    }

    /// Builds criteria from runtime entries in the supplied order.
    public init(pairs: [(String, JSONValue)]) {
        self.init(entries: pairs.map { Entry(key: $0.0, value: $0.1) })
    }

    public init(dictionaryLiteral elements: (String, JSONValue)...) {
        self.init(entries: elements.map { Entry(key: $0.0, value: $0.1) })
    }

    init(entries: [Entry]) {
        self.entries = []
        var positions: [String: Int] = [:]
        for entry in entries {
            if let index = positions[entry.key] {
                self.entries[index].value = entry.value
            } else {
                positions[entry.key] = self.entries.count
                self.entries.append(entry)
            }
        }
    }

    var dictionary: [String: JSONValue] {
        Dictionary(uniqueKeysWithValues: entries.map { ($0.key, $0.value) })
    }
}
