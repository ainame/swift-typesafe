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
    // Process startup, pipe reads, and shutdown can block for seconds on CI.
    // Keep them off the cooperative executor so unrelated retry budgets can advance.
    let port = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Int, any Error>) in
        DispatchQueue.global().async {
            do {
                try process.run()
                let data = pipe.fileHandleForReading.availableData
                let port = try #require(Int(String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)))
                continuation.resume(returning: port)
            } catch {
                if process.isRunning { process.terminate(); process.waitUntilExit() }
                continuation.resume(throwing: error)
            }
        }
    }
    do {
        try await body("http://127.0.0.1:\(port)")
    } catch {
        await stopServer(process)
        throw error
    }
    await stopServer(process)
}

private func stopServer(_ process: Process) async {
    await withCheckedContinuation { continuation in
        DispatchQueue.global().async {
            process.terminate()
            process.waitUntilExit()
            continuation.resume()
        }
    }
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

@Test(.timeLimit(.minutes(1)), arguments: [10, 192 * 1024 + 7])
func actualHTTPClientImageMultipartRoundTrip(size: Int) async throws {
    try await withServer { base in
        // Keep this transport test compatible with Python 3 before 3.14, which lacks compression.zstd.
        // Compression round trips are covered independently against libzstd in Upstream075Tests.
        let c = try TypeSafeClient(apiKey: "k", baseURL: base, compression: .disabled, environment: [:])
        let bytes = Data(repeating: 42, count: size)
        let result = try await c.systemOne(state: Image(data: bytes), model: "jev-preview") { Box("The subject") }
        #expect(result.answers.box.top == 0.1)
        #expect(result.answers.confidence == nil)
        #expect(result.rawHTTPResponse?.headers.first { $0.key.lowercased() == "x-seen-assets" }?.value == "1")
        #expect(result.rawHTTPResponse?.headers.first { $0.key.lowercased() == "x-seen-asset-bytes" }?.value == String(size))
    }
}

@Test(.timeLimit(.minutes(1))) func actualHTTPClientReplaysSegmentedUpload() async throws {
    try await withServer { base in
        let c = try TypeSafeClient(apiKey: "k", baseURL: base + "/retry", retry: .init(maxRetries: 1),
                                   compression: .disabled, environment: [:])
        let bytes = Data(repeating: 42, count: 192 * 1024 + 7)
        let result = try await c.systemOne(state: Image(data: bytes)) { Box("Subject") }
        #expect(result.rawHTTPResponse?.headers.first { $0.key.lowercased() == "x-seen-retry" }?.value == "1")
        #expect(result.rawHTTPResponse?.headers.first { $0.key.lowercased() == "x-seen-asset-bytes" }?.value == String(bytes.count))
    }
}

@Test(.timeLimit(.minutes(1))) func actualHTTPClientPostBodyLimit() async throws {
    try await withServer { base in
        let c = try TypeSafeClient(apiKey: "k", baseURL: base + "/large", retry: .init(maxRetries: 0),
                                   compression: .disabled, transport: HTTPClientTransport(maximumResponseBytes: 1024), environment: [:])
        await #expect(throws: TypeSafeError.self) {
            _ = try await c.systemOne(state: Image(data: Data([1, 2, 3])), questions: ["q": .box()])
        }
    }
}

@Test(.timeLimit(.minutes(1)), arguments: ["stall", "slowbody"], ["get", "post"])
func actualHTTPClientTimeoutIncludesBody(path: String, method: String) async throws {
    try await withServer { base in
        let c = try TypeSafeClient(apiKey: "k", baseURL: base + "/" + path, timeout: 0.1, retry: .init(maxRetries: 0), environment: [:])
        do {
            if method == "get" { _ = try await c.models.list() }
            else { _ = try await c.systemOne(state: Image(data: Data([1, 2, 3])), questions: ["q": .box()]) }
            Issue.record("Expected timeout")
        } catch TypeSafeError.timeout(let seconds) { #expect(seconds == 0.1) }
    }
}

@Test(.timeLimit(.minutes(1)), arguments: ["get", "post"])
func actualHTTPClientCancellation(method: String) async throws {
    try await withServer { base in
        let c = try TypeSafeClient(apiKey: "k", baseURL: base + "/stall", environment: [:])
        let task = Task {
            if method == "get" { _ = try await c.models.list() }
            else { _ = try await c.systemOne(state: Image(data: Data([1, 2, 3])), questions: ["q": .box()]) }
        }
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
