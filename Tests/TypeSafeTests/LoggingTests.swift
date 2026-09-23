import Foundation
import Logging
import Synchronization
import Testing
@testable import TypeSafe

private final class LogRecorder: Sendable {
    let entries = Mutex<[String]>([])
}
private struct RecordingLogHandler: LogHandler {
    let recorder: LogRecorder
    var metadata: Logger.Metadata = [:]
    var logLevel: Logger.Level = .debug
    subscript(metadataKey key: String) -> Logger.Metadata.Value? {
        get { metadata[key] }
        set { metadata[key] = newValue }
    }
    func log(event: LogEvent) {
        recorder.entries.withLock { $0.append(event.message.description + String(describing: event.metadata)) }
    }
}

@Test(arguments: ["debug", "info", "off"])
func loggingLevelsAndRedaction(level: String) async throws {
    let recorder = LogRecorder()
    let logger = Logger(label: "test") { _ in RecordingLogHandler(recorder: recorder) }
    let mock = MockTransport { _, _ in response(modelsFixture, headers: ["set-cookie": "response-credential", "x-secret": "hidden-response"]) }
    let c = try TypeSafeClient(apiKey: "api-credential", headers: ["x-access-token": "hidden-token", "Cookie": "cookie-credential", "x-visible": "visible-value"], transport: mock, logger: logger, environment: ["TYPESAFE_LOG_LEVEL": level])
    _ = try await c.models.list()
    let logs = recorder.entries.withLock { $0.joined(separator: "\n") }
    for secret in ["api-credential", "response-credential", "hidden-response", "hidden-token", "cookie-credential"] {
        #expect(!logs.contains(secret))
    }
    switch level {
    case "debug": #expect(logs.contains("visible-value")); #expect(logs.contains("***"))
    case "info": #expect(logs.contains("200")); #expect(!logs.contains("visible-value"))
    default: #expect(logs.isEmpty)
    }
}

private struct EchoedCredentialError: Error, CustomStringConvertible {
    let description: String
}

@Test(arguments: ["plain-secret", "quo'te\"slash\\tail"])
func transportErrorRedactsCredentials(credential: String) async throws {
    let provider = "provider-secret"
    let mock = MockTransport { request, _ in
        let encoded = String(decoding: try JSONEncoder().encode(credential), as: UTF8.self)
        throw EchoedCredentialError(description: "header=\(request.headers["authorization", default: ""]) json=\(encoded) provider=\(provider)")
    }
    let c = try TypeSafeClient(apiKey: credential, retry: .init(maxRetries: 0),
        headers: ["x-client-secret": provider], transport: mock, environment: [:])
    do {
        _ = try await c.models.list()
        Issue.record("Expected a connection error")
    } catch let error as TypeSafeError {
        guard case .connection(let message) = error else { Issue.record("Expected a connection error"); return }
        #expect(message.contains("***"))
        #expect(!message.contains(credential))
        #expect(!message.contains(provider))
        #expect(!message.contains("Bearer \(credential)"))
    }
}

@Test func unknownAnswersProduceWarning() async throws {
    let recorder = LogRecorder()
    let logger = Logger(label: "test") { _ in RecordingLogHandler(recorder: recorder) }
    let mock = MockTransport { _, _ in response(#"{"model":"m","usage":{},"answers":{"new":{"type":"future"}}}"#) }
    let c = try TypeSafeClient(apiKey: "k", transport: mock, logger: logger, environment: ["TYPESAFE_LOG_LEVEL": "warning"])
    _ = try await c.systemOne(state: "s", questions: ["q": .noul()])
    #expect(recorder.entries.withLock { $0.contains { $0.contains("unrecognized type 'future'") } })
}
