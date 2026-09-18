import Foundation

/// Retry settings match Python 0.6.0. Per-call policies replace the client policy.
public struct RetryPolicy: Sendable {
    public var maxRetries: Int
    public var backoffInitial: Double
    public var backoffMax: Double
    public var backoffJitter: Double
    public var httpStatuses: Set<Int>
    public var respectRetryAfter: Bool
    public var retryConnectionErrors: Bool
    public var retryTimeouts: Bool
    /// A retry scheduling budget, including previous attempts and sleeps. Does not interrupt an active attempt.
    public var timeout: Double?
    /// Additional errors to retry, analogous to Python's exception set and predicate.
    public var predicate: (@Sendable (any Error) -> Bool)?

    public init(
        maxRetries: Int = 2, backoffInitial: Double = 0.5, backoffMax: Double = 5,
        backoffJitter: Double = 0.25, httpStatuses: Set<Int> = Set([408, 429]).union(Set(500..<600)),
        respectRetryAfter: Bool = true, retryConnectionErrors: Bool = true, retryTimeouts: Bool = true,
        timeout: Double? = 30, predicate: (@Sendable (any Error) -> Bool)? = nil
    ) {
        self.maxRetries = maxRetries
        self.backoffInitial = backoffInitial
        self.backoffMax = backoffMax
        self.backoffJitter = backoffJitter
        self.httpStatuses = httpStatuses
        self.respectRetryAfter = respectRetryAfter
        self.retryConnectionErrors = retryConnectionErrors
        self.retryTimeouts = retryTimeouts
        self.timeout = timeout
        self.predicate = predicate
    }

    func validate() throws {
        guard maxRetries >= 0 else { throw TypeSafeError.configuration("maxRetries must be nonnegative.") }
        for (name, value) in [("backoffInitial", backoffInitial), ("backoffMax", backoffMax)] {
            guard value.isFinite, value >= 0 else { throw TypeSafeError.configuration("\(name) must be finite and nonnegative.") }
        }
        guard backoffJitter.isFinite, (0...1).contains(backoffJitter) else {
            throw TypeSafeError.configuration("backoffJitter must be between zero and one.")
        }
        if let timeout { try validateTimeout(timeout) }
    }

    func shouldRetry(_ error: any Error) -> Bool {
        if error is CancellationError { return false }
        let builtin: Bool
        switch error {
        case TypeSafeError.timeout: builtin = retryTimeouts
        case TypeSafeError.connection: builtin = retryConnectionErrors
        case TypeSafeError.api(let error): builtin = httpStatuses.contains(error.status)
        default: builtin = false
        }
        return builtin || (predicate?(error) ?? false)
    }

    func delay(attempt: Int, error: any Error, random: Double = Double.random(in: 0...1)) -> Double {
        if respectRetryAfter, case TypeSafeError.api(let api) = error,
           let delay = Self.retryAfter(headers: api.headers) { return delay }
        guard backoffInitial > 0, backoffMax > 0 else { return 0 }
        let capExponent = log2(backoffMax) - log2(backoffInitial)
        let exponential = Double(attempt) >= capExponent ? backoffMax : Double(sign: .plus, exponent: attempt, significand: backoffInitial)
        let jittered = exponential * (1 - random * backoffJitter)
        // Avoid overflow while preserving Python's millisecond rounding for ordinary delays.
        let rounded = jittered < Double.greatestFiniteMagnitude / 1000 ? (jittered * 1000).rounded() / 1000 : jittered
        return min(exponential, rounded)
    }

    /// Parses retry-after-ms first, then Retry-After seconds or an HTTP date. Returns seconds.
    public static func retryAfter(headers: [String: String], now: Date = Date()) -> Double? {
        let normalized = Dictionary(headers.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { _, last in last })
        for (name, multiplier) in [("retry-after-ms", 0.001), ("retry-after", 1.0)] {
            guard let raw = normalized[name] else { continue }
            let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if let value = Double(trimmed.isEmpty ? "0" : trimmed) {
                if value.isFinite, value >= 0, (value * (name == "retry-after" ? 1000 : 1)).isFinite { return value * multiplier }
                if value.isFinite, value < 0, name == "retry-after" { return nil }
            } else if name == "retry-after" {
                let formatter = DateFormatter()
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.timeZone = TimeZone(secondsFromGMT: 0)
                for format in ["EEE, dd MMM yyyy HH:mm:ss zzz", "EEEE, dd-MMM-yy HH:mm:ss zzz", "EEE MMM d HH:mm:ss yyyy"] {
                    formatter.dateFormat = format
                    if let date = formatter.date(from: raw) { return max(0, date.timeIntervalSince(now)) }
                }
            }
        }
        return nil
    }
}

func validateTimeout(_ timeout: Double) throws {
    guard timeout.isFinite, timeout > 0 else { throw TypeSafeError.configuration("timeout must be positive and finite.") }
}

extension Duration {
    var secondsValue: Double {
        let parts = components
        return Double(parts.seconds) + Double(parts.attoseconds) / 1e18
    }
}
