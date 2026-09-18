import Foundation
import Logging

public struct RequestOptions: Sendable {
    public var timeout: Double?
    public var retry: RetryPolicy?
    public var headers: [String: String]
    public init(timeout: Double? = nil, retry: RetryPolicy? = nil, headers: [String: String] = [:]) {
        self.timeout = timeout; self.retry = retry; self.headers = headers
    }
}

/// Concurrent, async-only TypeSafe client. Configuration is immutable and retry state is per call.
public struct TypeSafeClient: Sendable, CustomStringConvertible {
    public static let version = "0.6.0"
    public static let defaultBaseURL = "https://api.typesafe.ai"
    public static let defaultModel = "jev-latest"
    public static let defaultTimeout = 10.0

    private let apiKey: String
    public let baseURL: String
    public let model: String
    public let timeout: Double
    public let retry: RetryPolicy
    private let headers: [String: String]
    private let transport: any TypeSafeTransport
    private let logger: Logger
    private let loggingDisabled: Bool
    public var description: String { "TypeSafeClient(model: \(model))" }

    public init(
        apiKey: String? = nil, baseURL: String? = nil, model: String? = nil,
        timeout: Double = Self.defaultTimeout, retry: RetryPolicy = RetryPolicy(),
        headers: [String: String] = [:], transport: any TypeSafeTransport = HTTPClientTransport(),
        logger: Logger? = nil, environment: [String: String] = ProcessInfo.processInfo.environment
    ) throws {
        func resolve(_ value: String?, _ variable: String, _ fallback: String? = nil) -> String? {
            if let value { return value }
            let env = environment[variable]?.trimmingCharacters(in: .whitespacesAndNewlines)
            return env.flatMap { $0.isEmpty ? nil : $0 } ?? fallback
        }
        guard let key = resolve(apiKey, "TYPESAFE_API_KEY") else {
            throw TypeSafeError.configuration("No API key provided. Pass apiKey or set TYPESAFE_API_KEY.")
        }
        try validateTimeout(timeout)
        try retry.validate()
        self.apiKey = key
        var base = resolve(baseURL, "TYPESAFE_BASE_URL", Self.defaultBaseURL)!
        while base.hasSuffix("/") { base.removeLast() }
        guard let components = URLComponents(string: base), ["http", "https"].contains(components.scheme?.lowercased() ?? ""),
              components.host != nil, components.query == nil, components.fragment == nil else {
            throw TypeSafeError.configuration("baseURL must be an HTTP(S) URL without a query or fragment.")
        }
        self.baseURL = base
        self.model = resolve(model, "TYPESAFE_DEFAULT_MODEL", Self.defaultModel)!
        self.timeout = timeout
        self.retry = retry
        self.headers = headers
        self.transport = transport
        var log = logger ?? Logger(label: "typesafe_sdk")
        let level = environment["TYPESAFE_LOG_LEVEL"]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        loggingDisabled = level == "off"
        if logger == nil { log.logLevel = .warning }
        switch level {
        case "debug": log.logLevel = .debug
        case "info": log.logLevel = .info
        case "warn", "warning": log.logLevel = .warning
        case "error": log.logLevel = .error
        default: break
        }
        self.logger = log
    }

    public var models: Models { Models(client: self) }

    public struct Models: Sendable {
        let client: TypeSafeClient
        public func list(options: RequestOptions = RequestOptions()) async throws -> ListModelsResponse {
            try await client.listModels(options: options)
        }
    }

    public func listModels(options: RequestOptions = RequestOptions()) async throws -> ListModelsResponse {
        try await execute(method: "GET", path: "/v1/models", body: nil, options: options) { raw, endpoint in
            var result: ListModelsResponse = try Self.decode(raw, endpoint: endpoint)
            result.rawHTTPResponse = raw
            return result
        }
    }

    public func systemOne(
        state: JSONValue, questions: [String: Question], model: String? = nil,
        extraBody: [String: JSONValue] = [:], options: RequestOptions = RequestOptions()
    ) async throws -> SystemOneResponse {
        guard state.isContent else { throw TypeSafeError.configuration("state must be text, an object, or an array.") }
        guard !questions.isEmpty else { throw TypeSafeError.configuration("At least one question is required.") }
        for (name, question) in questions { try question.validate(name: name) }
        var body: [String: JSONValue] = [
            "state": state, "model": .string(model ?? self.model),
            "questions": .object(questions.mapValues { .object($0.payload) }),
        ]
        body.merge(extraBody, uniquingKeysWith: { _, last in last })
        let data: Data
        do { data = try JSONEncoder().encode(body) }
        catch { throw TypeSafeError.encoding("The request body could not be encoded as JSON.") }
        return try await execute(method: "POST", path: "/v1/systemone", body: data, options: options) { raw, endpoint in
            var result: SystemOneResponse = try Self.decode(raw, endpoint: endpoint)
            result.rawHTTPResponse = raw
            return result
        }
    }

    private func execute<Result: Sendable>(
        method: String, path: String, body: Data?, options: RequestOptions,
        parse: @Sendable (RawHTTPResponse, String) throws -> Result
    ) async throws -> Result {
        let timeout = options.timeout ?? timeout
        let retry = options.retry ?? retry
        try validateTimeout(timeout)
        try retry.validate()
        guard let url = URL(string: baseURL + path) else { throw TypeSafeError.configuration("Invalid request URL.") }
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        components.user = nil; components.password = nil; components.query = nil; components.fragment = nil
        let endpoint = "\(method) \(components.string ?? path)"
        var merged: [String: String] = [:]
        for source in [headers, options.headers] {
            for (name, value) in source { merged[name.lowercased()] = value }
        }
        merged.removeValue(forKey: "x-typesafe-retry-count")
        merged["authorization"] = "Bearer \(apiKey)"
        merged["accept"] = "application/json"
        merged["user-agent"] = "typesafe-sdk/\(Self.version)"
        merged["x-typesafe-sdk"] = "typesafe-sdk/\(Self.version)"
        merged["x-typesafe-runtime"] = "swift/6.4 (\(Self.platform))"
        if body != nil { merged["content-type"] = "application/json" }
        let started = ContinuousClock.now
        var attempt = 0
        while true {
            try Task.checkCancellation()
            var attemptHeaders = merged
            if attempt > 0 { attemptHeaders["x-typesafe-retry-count"] = String(attempt) }
            let request = TransportRequest(method: method, url: url, headers: attemptHeaders, body: body, timeout: timeout)
            logWire("\(endpoint) ->", headers: attemptHeaders, body: body)
            do {
                let raw = try await send(request)
                try Task.checkCancellation()
                if !loggingDisabled { logger.info("\(endpoint) <- \(raw.status) (request \(raw.requestID ?? "-"))") }
                logWire("\(endpoint) <-", headers: raw.headers, body: raw.body)
                guard (200..<300).contains(raw.status) else {
                    throw TypeSafeError.api(APIError(status: raw.status, body: decodeBody(raw.body), headers: raw.headers, endpoint: endpoint))
                }
                return try parse(raw, endpoint)
            } catch {
                try Task.checkCancellation()
                guard attempt < retry.maxRetries, retry.shouldRetry(error) else { throw error }
                let delay = retry.delay(attempt: attempt, error: error)
                if let budget = retry.timeout, started.duration(to: .now).secondsValue + delay >= budget { throw error }
                if !loggingDisabled { logger.info("\(endpoint) retry \(attempt + 1)") }
                try await sleep(seconds: delay)
                attempt += 1
            }
        }
    }

    private func send(_ request: TransportRequest) async throws -> RawHTTPResponse {
        do {
            return try await withThrowingTaskGroup(of: RawHTTPResponse.self) { group in
                group.addTask { try await transport.send(request) }
                group.addTask {
                    try await sleep(seconds: request.timeout)
                    throw TypeSafeError.timeout(seconds: request.timeout)
                }
                defer { group.cancelAll() }
                return try await group.next()!
            }
        } catch is CancellationError { throw CancellationError() }
        catch let error as TypeSafeError { throw error }
        catch let error as URLError where error.code == .timedOut { throw TypeSafeError.timeout(seconds: request.timeout) }
        catch { throw TypeSafeError.connection("Connection error: \(error)") }
    }

    private static func decode<T: Decodable>(_ raw: RawHTTPResponse, endpoint: String) throws -> T {
        do { return try JSONDecoder().decode(T.self, from: raw.body) }
        catch let error as DecodingError {
            let path = decodingPath(error)
            throw TypeSafeError.responseValidation(APIError(status: raw.status, body: decodeBody(raw.body), headers: raw.headers, endpoint: endpoint,
                                                           message: "Invalid response data at '\(path)'."), fieldPath: path)
        }
    }

    private func logWire(_ message: String, headers: [String: String], body: Data?) {
        guard !loggingDisabled, logger.logLevel <= .debug else { return }
        logger.debug("\(message)", metadata: [
            "headers": .dictionary(headers.mapValuesWithKeys { name, value in .string(Self.isSecret(name) ? "***" : value) }),
            "body": .string(body.map { String(decoding: $0, as: UTF8.self) } ?? ""),
        ])
    }

    static func isSecret(_ name: String) -> Bool {
        let name = name.lowercased()
        return ["authorization", "proxy-authorization", "x-api-key", "api-key", "cookie", "set-cookie"].contains(name) || name.contains("token") || name.contains("secret")
    }

    private static var platform: String {
        #if os(Linux)
        "linux"
        #elseif os(macOS)
        "macOS"
        #elseif os(iOS)
        "iOS"
        #elseif os(tvOS)
        "tvOS"
        #elseif os(watchOS)
        "watchOS"
        #else
        "visionOS"
        #endif
    }
}

private extension Dictionary where Key == String, Value == String {
    func mapValuesWithKeys<T>(_ transform: (String, String) -> T) -> [String: T] {
        Dictionary<String, T>(uniqueKeysWithValues: map { ($0.key, transform($0.key, $0.value)) })
    }
}

/// Chunk large finite waits to avoid overflowing Duration's representation.
func sleep(seconds: Double) async throws {
    var remaining = seconds
    while remaining > 0 {
        let chunk = min(remaining, 86400)
        try await Task.sleep(for: .seconds(chunk))
        remaining -= chunk
    }
    try Task.checkCancellation()
}
