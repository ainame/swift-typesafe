import Foundation
import HTTPAPIs

// The backend is chosen by package traits so only one HTTP stack is compiled.
// AsyncHTTPClient wins when enabled; URLSession falls back to it off Darwin (see Package.swift).
#if AsyncHTTPClient || (URLSession && os(Linux))
import AHCHTTPClient
import AsyncHTTPClient

private func defaultHTTPClient() -> AsyncHTTPClient.HTTPClient { .shared }
#elseif URLSession && canImport(Darwin)
import URLSessionHTTPClient

private func defaultHTTPClient() -> URLSessionHTTPClient { .shared }
#endif

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
/// Injected clients remain caller-owned. The default uses the shared client of the backend selected by
/// the `URLSession` (default) or `AsyncHTTPClient` package trait.
public struct HTTPClientTransport: TypeSafeTransport {
    private let operation: @Sendable (TransportRequest) async throws -> RawHTTPResponse

    public init(maximumResponseBytes: Int = 16 * 1024 * 1024) {
        #if AsyncHTTPClient || (URLSession && os(Linux)) || (URLSession && canImport(Darwin))
        self.init(client: defaultHTTPClient(), maximumResponseBytes: maximumResponseBytes)
        #else
        operation = { _ in
            throw TypeSafeError.configuration(
                "No default HTTP client: enable the URLSession or AsyncHTTPClient trait, or inject a transport."
            )
        }
        #endif
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
