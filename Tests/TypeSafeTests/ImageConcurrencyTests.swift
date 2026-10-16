import Foundation
import Testing
@testable import TypeSafe

/// A controlled pause for overlapping attachment scopes, without sleeps or locks.
private actor PausedImageRead {
    private var completion: CheckedContinuation<Data, any Error>?
    private var started: [CheckedContinuation<Void, Never>] = []
    func read() async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            completion = continuation
            let ready = started
            started = []
            for waiter in ready { waiter.resume() }
        }
    }
    func waitUntilStarted() async {
        if completion != nil { return }
        await withCheckedContinuation { started.append($0) }
    }
    func finish(_ result: Result<Data, any Error>) {
        completion!.resume(with: result)
        completion = nil
    }
}

@Test func imageValueCopiesKeepTheirAssetReference() {
    let image = Image(data: Data([1, 2, 3]))
    let copy = image
    #expect(copy == image)
    #expect(copy.description == image.description)
    #expect(Image(data: Data([1, 2, 3])) != image)
}

@Test(arguments: [false, true]) func fileImageCanBeReadAfterMissingOrEmptyFile(empty: Bool) async throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: url) }
    if empty { try Data().write(to: url) }
    let image = Image(fileURL: url)
    await #expect(throws: TypeSafeError.self) { _ = try await image.resolve() }
    try Data([1, 2, 3]).write(to: url)
    #expect(try await image.resolve() == Data([1, 2, 3]))
}

@Test func fileImageNewRequestsRereadButRetriesKeepPreparedBytes() async throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: url) }
    let original = Data(repeating: 1, count: 2048)
    let replacement = Data(repeating: 2, count: 2048)
    try original.write(to: url)
    let image = Image(fileURL: url)
    let copy = image
    let mock = MockTransport { _, attempt in
        if attempt == 1 {
            try replacement.write(to: url)
            return response("{}", status: 429, headers: ["retry-after-ms": "0"])
        }
        return response()
    }
    let c = try TypeSafeClient(apiKey: "k", retry: .init(maxRetries: 1), compression: .disabled,
                               transport: mock, environment: [:])
    _ = try await c.systemOne(state: .image(image), questions: ["q": .box()])
    _ = try await c.systemOne(state: .image(copy), questions: ["q": .box()])
    let requests = await mock.requests
    try #require(requests.count == 3)
    #expect(requests[0].bodySegments?.contains(original) == true)
    #expect(requests[0].body == requests[1].body)
    #expect(requests[2].bodySegments?.contains(replacement) == true)
}

@Test(.timeLimit(.minutes(1))) func overlappingAttachmentScopesRemainVisibleAcrossTasksAndClientCopies() async throws {
    let source = PausedImageRead()
    let image = Image(data: Data([1, 2, 3]))
    let mock = MockTransport()
    let c = try TypeSafeClient(apiKey: "k", compression: .disabled, transport: mock, environment: [:])
    let copy = c
    let scope = Task {
        try await c.withAttachedAssets([image]) {
            _ = try await source.read()
            try Task.checkCancellation()
        }
    }
    await source.waitUntilStarted()
    try await copy.withAttachedAssets([image]) {
        _ = try await copy.systemOne(state: .string("Inspect \(image)"), questions: ["q": .box()])
    }
    // The second scope has ended, but the first task still holds this image on the shared client.
    _ = try await copy.systemOne(state: .string("Inspect \(image)"), questions: ["q": .box()])
    scope.cancel()
    await source.finish(.success(Data([1])))
    await #expect(throws: CancellationError.self) { _ = try await scope.value }
    #expect(await c.attachedImages.snapshot.isEmpty)
    _ = try await c.systemOne(state: .string("Inspect \(image)"), questions: ["q": .box()])
    let requests = await mock.requests
    #expect(requests.prefix(2).allSatisfy { $0.headers["content-type"]!.hasPrefix("multipart/") })
    #expect(requests.last?.headers["content-type"] == "application/json")
}

private final class CallerOwnedValue {}

@MainActor
@Test func actorAttachmentCleanupPreservesCallerIsolationAndNonSendableResults() async throws {
    let c = try client()
    let value = CallerOwnedValue()
    let returned = await c.withAttachedAssets([Image(data: Data([1]))]) { value }
    #expect(returned === value)
    #expect(await c.attachedImages.snapshot.isEmpty)
}

@Test(arguments: ["state", "questions"])
func imagePrecollectionHonorsExtraBodyOverrides(field: String) async throws {
    let image = Image(data: Data([1, 2, 3]))
    let mock = MockTransport()
    let c = try client(mock)
    if field == "state" {
        _ = try await c.systemOne(state: .image(image), questions: ["q": .box()], extraBody: ["state": .string(image.description)])
    } else {
        _ = try await c.systemOne(state: "s", questions: ["q": .box(instructions: .image(image))],
                                 extraBody: ["questions": ["q": ["type": "box", "instructions": .string(image.description)]]])
    }
    #expect(await mock.requests.first?.headers["content-type"] == "application/json")
}
