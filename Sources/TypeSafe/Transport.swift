import Foundation
import HTTPAPIs
import BasicContainers

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
    /// Immutable body segments. Streaming transports can send these without flattening the body.
    public let bodySegments: [Data]?
    /// Compatibility view for buffered transports. Accessing a multipart body combines its segments.
    public var body: Data? {
        guard let segments = bodySegments else { return nil }
        if segments.count == 1 { return segments[0] }
        var data = Data()
        data.reserveCapacity(segments.reduce(0) { $0 + $1.count })
        for segment in segments { data.append(segment) }
        return data
    }
    init(method: String, url: URL, headers: [String: String], body: RequestBody?, timeout: Double) {
        self.method = method; self.url = url; self.headers = headers
        bodySegments = body?.segments; self.timeout = timeout
    }
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
                let segments = request.bodySegments ?? []
                let length = segments.reduce(0) { $0 + $1.count }
                let body = HTTPClientRequestBody<Client.Writer>.seekable(knownLength: Int64(length)) { offset, writer in
                    var writer = writer
                    var skip = Int(offset)
                    for segment in segments {
                        if skip >= segment.count { skip -= segment.count; continue }
                        var position = skip
                        skip = 0
                        while position < segment.count {
                            try Task.checkCancellation()
                            let count = min(64 * 1024, segment.count - position)
                            var buffer = BasicContainers.UniqueArray<UInt8>(copying: segment.span.extracting(position..<(position + count)))
                            try await writer.write(buffer: &buffer)
                            position += count
                        }
                    }
                    var empty = BasicContainers.UniqueArray<UInt8>()
                    try await writer.finish(buffer: &empty, finalElement: nil)
                }
                let httpRequest = HTTPRequest(method: .post, url: request.url, headerFields: fields)
                result = try await client.perform(request: httpRequest, body: body, options: options) { response, reader in
                    var reader = reader
                    var data = Data()
                    var done = false
                    while !done {
                        try await reader.read { (chunk: inout Client.Reader.Buffer, finalElement: HTTPFields??) in
                            if finalElement != nil || chunk.count == 0 { done = true }
                            var consumer = chunk.consumeAll()
                            while true {
                                var span = consumer.drainNext()
                                if span.isEmpty { break }
                                try span.withUnsafeMutableBufferPointer { bytes, _ in
                                    guard bytes.count <= maximumResponseBytes - data.count else { throw ResponseLimitExceeded() }
                                    data.append(contentsOf: bytes)
                                }
                            }
                        }
                    }
                    return (response, data)
                }
            }
            let headers = Dictionary(result.response.headerFields.map { ($0.name.rawName, $0.value) }, uniquingKeysWith: { first, last in first + ", " + last })
            return RawHTTPResponse(status: result.response.status.code, headers: headers, body: result.bodyData)
        }
    }

    public func send(_ request: TransportRequest) async throws -> RawHTTPResponse { try await operation(request) }
}

private struct ResponseLimitExceeded: Error {}
