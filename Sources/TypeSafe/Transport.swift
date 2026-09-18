import Foundation
import HTTPClient

/// A fully prepared request. Custom transports should cooperate with task cancellation.
public struct TransportRequest: Sendable {
    public let method: String
    public let url: URL
    public let headers: [String: String]
    public let body: Data?
    public let timeout: Double
}

public protocol TypeSafeTransport: Sendable {
    func send(_ request: TransportRequest) async throws -> RawHTTPResponse
}

/// Adapter for Apple's proposed common HTTPClient API. Inject a client to configure TLS and pooling.
/// Injected clients remain caller-owned; the default uses DefaultHTTPClient.shared.
public struct HTTPClientTransport: TypeSafeTransport {
    private let operation: @Sendable (TransportRequest) async throws -> RawHTTPResponse

    public init(maximumResponseBytes: Int = 16 * 1024 * 1024) {
        self.init(client: DefaultHTTPClient.shared, maximumResponseBytes: maximumResponseBytes)
    }

    public init<Client: HTTPAPIs.HTTPClient & Copyable>(
        client: Client, options: Client.RequestOptions? = nil, maximumResponseBytes: Int = 16 * 1024 * 1024
    ) {
        operation = { request in
            guard maximumResponseBytes > 0 else { throw TypeSafeError.configuration("maximumResponseBytes must be positive.") }
            var client = client
            var fields = HTTPFields()
            for (name, value) in request.headers {
                guard let name = HTTPField.Name(name) else { throw TypeSafeError.configuration("Invalid HTTP header name.") }
                fields[name] = value
            }
            let result: (response: HTTPResponse, bodyData: Data)
            if request.method == "GET" {
                result = try await client.get(url: request.url, headerFields: fields, options: options, collectUpTo: maximumResponseBytes)
            } else {
                result = try await client.post(url: request.url, headerFields: fields, bodyData: request.body ?? Data(), options: options, collectUpTo: maximumResponseBytes)
            }
            let headers = Dictionary(result.response.headerFields.map { ($0.name.rawName, $0.value) }, uniquingKeysWith: { first, last in first + ", " + last })
            return RawHTTPResponse(status: result.response.status.code, headers: headers, body: result.bodyData)
        }
    }

    public func send(_ request: TransportRequest) async throws -> RawHTTPResponse { try await operation(request) }
}
