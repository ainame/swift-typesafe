#if os(macOS) || os(Linux)
import Foundation
import Testing
import TypeSafe

private func withServer(_ body: (String) async throws -> Void) async throws {
    let process = Process()
    let pipe = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["python3", "-u", URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Support/server.py").path]
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    try process.run()
    defer { process.terminate(); process.waitUntilExit() }
    let data = pipe.fileHandleForReading.availableData
    let port = try #require(Int(String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)))
    try await body("http://127.0.0.1:\(port)")
}

@Test(.timeLimit(.minutes(1))) func actualHTTPClientRoundTrip() async throws {
    try await withServer { base in
        let c = try TypeSafeClient(apiKey: "loopback-key", baseURL: base, environment: [:])
        let models = try await c.models.list()
        #expect(models.models.first?.name == "loopback")
        #expect(models.requestID == "loopback-request")
        #expect(models.rawHTTPResponse?.headers.first { $0.key.lowercased() == "x-seen-authorization" }?.value == "Bearer loopback-key")
        let result = try await c.systemOne(state: ["message": "Hello"], questions: TicketQuestions.self)
        #expect(result.answers.spam.noul == 0.75)
        #expect(result.answers.quality.legend[0] == "bad")
        let retryClient = try TypeSafeClient(apiKey: "k", baseURL: base + "/retry", environment: [:])
        let retried = try await retryClient.models.list()
        #expect(retried.rawHTTPResponse?.headers.first { $0.key.lowercased() == "x-seen-retry" }?.value == "1")
    }
}

@Test(.timeLimit(.minutes(1)), arguments: ["stall", "slowbody"])
func actualHTTPClientTimeoutIncludesBody(path: String) async throws {
    try await withServer { base in
        let c = try TypeSafeClient(apiKey: "k", baseURL: base + "/" + path, timeout: 0.1, retry: .init(maxRetries: 0), environment: [:])
        do {
            _ = try await c.models.list()
            Issue.record("Expected timeout")
        } catch TypeSafeError.timeout(let seconds) { #expect(seconds == 0.1) }
    }
}

@Test(.timeLimit(.minutes(1))) func actualHTTPClientCancellation() async throws {
    try await withServer { base in
        let c = try TypeSafeClient(apiKey: "k", baseURL: base + "/stall", environment: [:])
        let task = Task { try await c.models.list() }
        try await Task.sleep(for: .milliseconds(100))
        task.cancel()
        await #expect(throws: CancellationError.self) { _ = try await task.value }
    }
}

@Test(.timeLimit(.minutes(1))) func actualHTTPClientBodyLimit() async throws {
    try await withServer { base in
        let c = try TypeSafeClient(apiKey: "k", baseURL: base + "/large", retry: .init(maxRetries: 0), transport: HTTPClientTransport(maximumResponseBytes: 1024), environment: [:])
        await #expect(throws: TypeSafeError.self) { _ = try await c.models.list() }
    }
}
#endif
