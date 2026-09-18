import Foundation

public enum TypeSafeError: Error, Sendable, CustomStringConvertible {
    case configuration(String)
    case encoding(String)
    case connection(String)
    case timeout(seconds: Double)
    case api(APIError)
    case responseValidation(APIError, fieldPath: String)

    public var description: String {
        switch self {
        case .configuration(let message), .encoding(let message), .connection(let message): message
        case .timeout(let seconds): "Request timed out (timeout=\(seconds))."
        case .api(let error): error.description
        case .responseValidation(let error, _): error.description
        }
    }
}

public struct APIError: Error, Sendable, CustomStringConvertible {
    public enum Kind: String, Sendable {
        case badRequest, authentication, permissionDenied, notFound, unprocessableEntity, rateLimit, internalServer, other
    }
    public let status: Int
    public let body: JSONValue
    public let headers: [String: String]
    public let endpoint: String?
    public let message: String
    public var requestID: String? { header("x-typesafe-request-id") }
    public var retryAfterMilliseconds: Double? { RetryPolicy.retryAfter(headers: headers).map { $0 * 1000 } }
    public var kind: Kind {
        switch status {
        case 400: .badRequest
        case 401: .authentication
        case 403: .permissionDenied
        case 404: .notFound
        case 422: .unprocessableEntity
        case 429: .rateLimit
        case 500...: .internalServer
        default: .other
        }
    }

    public init(status: Int, body: JSONValue, headers: [String: String] = [:], endpoint: String? = nil, message: String? = nil) {
        self.status = status
        self.body = body
        self.headers = headers
        self.endpoint = endpoint
        self.message = message ?? Self.extractMessage(body) ?? Self.fallback(body)
    }

    public var description: String {
        let context = endpoint.map { "\($0): " } ?? ""
        let detail = message.isEmpty ? "\(status)" : "\(status) \(message)"
        return context + detail + (requestID.map { " (request_id=\($0))" } ?? "")
    }

    private func header(_ name: String) -> String? {
        headers.first { $0.key.lowercased() == name }?.value
    }

    static func extractMessage(_ body: JSONValue) -> String? {
        if case .string(let text) = body { return text.isEmpty ? nil : text }
        for candidate in [body["error"], body["error"]?["message"], body["message"], body["detail"], body["detail"]?["message"]] {
            if let text = candidate?.stringValue { return text }
        }
        if case .array(let entries) = body["detail"] {
            let messages = entries.compactMap { entry -> String? in
                guard let message = entry["msg"]?.stringValue else { return nil }
                var path: [String] = []
                if case .array(let location) = entry["loc"] {
                    path = location.compactMap {
                        switch $0 {
                        case .string("body"): nil
                        case .string(let value): value
                        case .integer(let value): String(value)
                        default: nil
                        }
                    }
                }
                return path.isEmpty ? message : path.joined(separator: ".") + ": " + message
            }
            if !messages.isEmpty { return messages.joined(separator: "; ") }
        }
        return nil
    }

    private static func fallback(_ body: JSONValue) -> String {
        if body == .null { return "status code (no body)" }
        let text = body.stringValue ?? String(decoding: (try? JSONEncoder().encode(body)) ?? Data(), as: UTF8.self)
        return String(text.prefix(200)) + (text.count > 200 ? "…" : "")
    }
}
