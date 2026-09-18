import Foundation
@testable import TypeSafe

let resultFixture = #"""
{"model":"jev-latest","usage":{"input_tokens":12,"output_tokens":3},"answers":{
 "spam":{"type":"noul","noul":0.98},
 "tone":{"type":"choice","choice":"friendly","confidence":0.9,"probabilities":{"friendly":0.9,"hostile":0.1}},
 "quality":{"type":"score","score":1.7,"confidence":0.8,"legend":{"0":"bad","1":"ok","2":"great"},"probabilities":{"0":0.1,"1":0.1,"2":0.8}}
}}
"""#
let modelsFixture = #"{"models":[{"name":"jev-latest","description":"Fast model","release_date":"2026-08-01"}]}"#

func response(_ json: String = resultFixture, status: Int = 200, headers: [String: String] = ["x-typesafe-request-id": "req_123"]) -> RawHTTPResponse {
    RawHTTPResponse(status: status, headers: headers, body: Data(json.utf8))
}

actor MockTransport: TypeSafeTransport {
    private(set) var requests: [TransportRequest] = []
    let handler: @Sendable (TransportRequest, Int) async throws -> RawHTTPResponse
    init(_ handler: @escaping @Sendable (TransportRequest, Int) async throws -> RawHTTPResponse = { _, _ in response() }) { self.handler = handler }
    func send(_ request: TransportRequest) async throws -> RawHTTPResponse {
        requests.append(request)
        return try await handler(request, requests.count)
    }
}

func client(_ transport: any TypeSafeTransport = MockTransport(), retry: RetryPolicy = .init(maxRetries: 0)) throws -> TypeSafeClient {
    try TypeSafeClient(apiKey: "test-key", retry: retry, transport: transport, environment: [:])
}
