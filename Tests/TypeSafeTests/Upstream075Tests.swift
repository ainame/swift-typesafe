import Foundation
import Testing
import libzstd
@testable import TypeSafe

private let boxFixture = #"{"model":"jev-preview","usage":{},"answers":{"subject":{"type":"box","box":{"top":0.1,"bottom":0.9,"left":0.2,"right":0.8},"confidence":null}}}"#

@QuestionSet
private struct ImageQuestions {
    @Box("The subject") var subject: BoxCoordinates
}

@Test func boxDynamicMacroBuilderAndCustomResponse() async throws {
    let mock = MockTransport { _, _ in response(boxFixture) }
    let c = try client(mock)
    let dynamic = try await c.systemOne(state: "photo", questions: ["subject": .box()])
    #expect(dynamic.boxes["subject"]?.box.top == 0.1)
    #expect(dynamic.boxes["subject"]?.confidence == nil)
    #expect(dynamic.nouls.isEmpty)
    let typed = try await c.systemOne(state: "photo", questions: ImageQuestions.self)
    #expect(typed.answers.subject == dynamic.boxes["subject"])
    let builderMock = MockTransport { _, _ in response(boxFixture.replacingOccurrences(of: "subject", with: "question_0")) }
    let built = try await client(builderMock).systemOne(state: "photo") { Box("Subject") }
    #expect(built.answers.box == typed.answers.subject.box)
    struct Custom: Decodable, Sendable { let answers: [String: BoxAnswer] }
    let custom = try await c.systemOne(state: "photo", questions: ["subject": .box()], responseModel: Custom.self)
    #expect(custom.answers["subject"] == typed.answers.subject)
    let encoded = try JSONEncoder().encode(dynamic)
    let json = try JSONDecoder().decode(JSONValue.self, from: encoded)
    #expect(json["answers"]?["subject"]?["confidence"] == .null)
    #expect(json["answers"]?["subject"]?["type"] == "box")
}

@Test(arguments: [
    #"{"box":{"top":0,"bottom":1,"left":0,"right":1}}"#,
    #"{"box":{"top":"bad","bottom":1,"left":0,"right":1},"confidence":null}"#,
    #"{"box":{"top":0,"bottom":1,"left":0},"confidence":null}"#,
    #"{"box":null,"confidence":null}"#,
])
func invalidBoxResponsesKeepValidationContext(answer: String) async throws {
    let mock = MockTransport { _, _ in
        response("{\"model\":\"m\",\"usage\":{},\"answers\":{\"subject\":{\"type\":\"box\"," + answer.dropFirst() + "}}")
    }
    do {
        _ = try await client(mock).systemOne(state: "photo", questions: ["subject": .box()])
        Issue.record("Expected invalid Box response")
    } catch TypeSafeError.responseValidation(let error, let fieldPath) {
        #expect(fieldPath.hasPrefix("answers.subject."))
        #expect(error.requestID == "req_123")
    }
}

@Test(arguments: [
    Question.noul(), .noul(criteria: [:]), .noul(criteria: ["true": nil, "false": nil]),
    .choice(criteria: [:]), .raw(["type": "choice", "criteria": [:]]),
    .raw(["type": "noul", "criteria": []]), .raw(["type": "noul", "criteria": nil]),
])
func upstreamValidationRejectsEmptyQuestions(question: Question) async throws {
    let mock = MockTransport()
    await #expect(throws: TypeSafeError.self) { _ = try await client(mock).systemOne(state: "s", questions: ["q": question]) }
    #expect(await mock.requests.isEmpty)
}

@Test func nonFiniteNumbersAreStringsAtEveryDepth() async throws {
    let mock = MockTransport()
    _ = try await client(mock).systemOne(state: ["values": [.number(.nan), .number(.infinity), .number(-.infinity)]],
        questions: ["q": .choice(instructions: ["n": .number(.nan)], criteria: ["a": ["n": .number(.infinity)]])],
        extraBody: ["extra": .number(-.infinity)])
    let json = try JSONDecoder().decode(JSONValue.self, from: #require(await mock.requests.first?.body))
    #expect(json["state"]?["values"] == ["NaN", "Infinity", "-Infinity"])
    #expect(json["questions"]?["q"]?["instructions"]?["n"] == "NaN")
    #expect(json["questions"]?["q"]?["criteria"]?["a"]?["n"] == "Infinity")
    #expect(json["extra"] == "-Infinity")
}

private func decompressed(_ data: Data) throws -> Data {
    let size = data.withUnsafeBytes { ZSTD_getFrameContentSize($0.baseAddress, $0.count) }
    #expect(size < 1_000_000)
    var result = Data(count: Int(size))
    let count = result.withUnsafeMutableBytes { output in
        data.withUnsafeBytes { input in ZSTD_decompress(output.baseAddress, output.count, input.baseAddress, input.count) }
    }
    #expect(ZSTD_isError(count) == 0)
    result.count = count
    return result
}

@Test(arguments: [1023, 1024, 1025])
func compressionThresholdAndRetries(size: Int) async throws {
    var encoder = RequestBodyEncoder()
    let base = try encoder.encode(state: "", model: TypeSafeClient.defaultModel, questions: ["q": .box()], extraBody: [:])
    let state = JSONValue.string(String(repeating: "a", count: size - base.count))
    let mock = MockTransport { _, attempt in
        attempt == 1 ? response("{}", status: 429, headers: ["retry-after-ms": "0"]) : response()
    }
    let c = try TypeSafeClient(apiKey: "k", retry: .init(maxRetries: 1), transport: mock, environment: [:])
    _ = try await c.systemOne(state: state, questions: ["q": .box()])
    let requests = await mock.requests
    #expect(requests.count == 2)
    #expect(requests[0].body == requests[1].body)
    #expect(requests[1].headers["x-typesafe-retry-count"] == "1")
    let data = try #require(requests[0].body)
    if size < 1024 {
        #expect(data.count == size)
        #expect(requests[0].headers["content-encoding"] == nil)
    } else {
        #expect(requests[0].headers["content-encoding"] == "zstd")
        #expect(try decompressed(data).count == size)
    }
}

@Test func compressionCanBeDisabled() async throws {
    let mock = MockTransport()
    let c = try TypeSafeClient(apiKey: "k", compression: .disabled, transport: mock, environment: [:])
    _ = try await c.systemOne(state: .string(String(repeating: "a", count: 2048)), questions: ["q": .box()])
    let request = try #require(await mock.requests.first)
    #expect(request.headers["content-encoding"] == nil)
    #expect(try JSONDecoder().decode(JSONValue.self, from: #require(request.body))["state"]?.stringValue?.count == 2048)
}

@Test func multipartAliasesReferencesAndBinaryBytes() async throws {
    let bytes = Data([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0, 255])
    let image = Image(data: bytes)
    let mock = MockTransport()
    let c = try TypeSafeClient(apiKey: "k", compression: .disabled, transport: mock, environment: [:])
    _ = try await c.systemOne(state: ["photo": .image(image), "reference": .string(image.description)], questions: [
        "q": .choice(instructions: .image(image), criteria: ["b": .image(image), "a": nil]),
    ], assets: ["<photo>": image, "<copy>": image])
    let request = try #require(await mock.requests.first)
    #expect(request.headers["content-type"]?.hasPrefix("multipart/form-data; boundary=") == true)
    let body = try #require(request.body)
    let text = String(decoding: body, as: UTF8.self)
    #expect(text.contains("name=\"request\"\r\nContent-Type: application/json"))
    #expect(text.components(separatedBy: "Content-Type: image/png").count == 4) // two aliases and the textual reference
    #expect(text.contains(#""photo":"<photo>""#)) // deterministic last alias in sorted order
    #expect(text.contains(#""criteria":{"b":"<photo>","a":null}"#))
    #expect(body.range(of: bytes) != nil)
}

@Test func inlineImagesAndCompressedMultipart() async throws {
    let image = Image(data: Data(repeating: 42, count: 2048))
    let mock = MockTransport()
    _ = try await client(mock).systemOne(state: .image(image), questions: ["q": .box()])
    let request = try #require(await mock.requests.first)
    #expect(request.headers["content-encoding"] == "zstd")
    #expect(request.headers["content-type"]?.hasPrefix("multipart/form-data;") == true)
    let data = try decompressed(#require(request.body))
    let text = String(decoding: data, as: UTF8.self)
    #expect(text.contains(image.description))
    #expect(text.contains("Content-Type: application/octet-stream"))
}

@Test func scopedAttachmentsNestAndCleanUpOnThrow() async throws {
    struct Expected: Error {}
    let image = Image(data: Data([0xff, 0xd8, 0xff, 1]))
    let mock = MockTransport()
    let c = try TypeSafeClient(apiKey: "k", compression: .disabled, transport: mock, environment: [:])
    await #expect(throws: Expected.self) {
        try await c.withAttachedAssets([image]) {
            try await c.withAttachedAssets([image]) {
                _ = try await c.systemOne(state: .string("Find \(image)"), questions: ["q": .box()])
            }
            _ = try await c.systemOne(state: .string("Find \(image)"), questions: ["q": .box()])
            throw Expected()
        }
    }
    _ = try await c.systemOne(state: .string("Find \(image)"), questions: ["q": .box()])
    let requests = await mock.requests
    #expect(requests.prefix(2).allSatisfy { $0.headers["content-type"]!.hasPrefix("multipart/") })
    #expect(requests.last?.headers["content-type"] == "application/json")
}

@Test func fileImageValuesReadCurrentBytesAcrossConcurrentCalls() async throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try Data([1, 2, 3]).write(to: url)
    defer { try? FileManager.default.removeItem(at: url) }
    let image = Image(fileURL: url)
    try await withThrowingTaskGroup(of: Data.self) { group in
        for _ in 0..<8 { group.addTask { try await image.resolve() } }
        for try await bytes in group { #expect(bytes == Data([1, 2, 3])) }
    }
    try Data([4]).write(to: url)
    #expect(try await image.resolve() == Data([4]))
}

@Test func assetsOverrideSkipsFileIOAndInvalidAssetsFailEarly() async throws {
    let missing = Image(fileURL: URL(fileURLWithPath: "/missing/\(UUID().uuidString)"))
    let mock = MockTransport()
    let c = try client(mock)
    _ = try await c.systemOne(state: .image(missing), questions: ["q": .box()], extraBody: ["assets": nil], assets: ["x": missing])
    #expect(await mock.requests.count == 1)
    await #expect(throws: TypeSafeError.self) {
        _ = try await c.systemOne(state: .image(missing), questions: ["q": .box()])
    }
    await #expect(throws: TypeSafeError.self) {
        _ = try await c.systemOne(state: "s", questions: ["q": .box()], assets: ["x": Image(data: Data())])
    }
    #expect(await mock.requests.count == 1)
    #expect(throws: TypeSafeError.self) { try Image.fromBase64("é") }
    #expect(throws: TypeSafeError.self) { try Image.fromBase64("??") }
    #expect(throws: TypeSafeError.self) { try Image.fromBase64("   ") }
    #expect(try await Image.fromBase64(" A Q I D \n").resolve() == Data([1, 2, 3]))
}

@Test(arguments: ["macro", "builder", "custom"])
func namedAssetsReachEveryQuestionAPI(api: String) async throws {
    let image = Image(data: Data([1, 2, 3]))
    let mock = MockTransport { _, _ in response(boxFixture) }
    let c = try TypeSafeClient(apiKey: "k", compression: .disabled, transport: mock, environment: [:])
    switch api {
    case "macro":
        _ = try await c.systemOne(state: "<photo>", questions: ImageQuestions.self, assets: ["<photo>": image])
    case "builder":
        let builderMock = MockTransport { _, _ in response(boxFixture.replacingOccurrences(of: "subject", with: "question_0")) }
        let builder = try TypeSafeClient(apiKey: "k", compression: .disabled, transport: builderMock, environment: [:])
        _ = try await builder.systemOne(state: "<photo>", assets: ["<photo>": image]) { Box("Subject") }
        #expect(await builderMock.requests.first?.headers["content-type"]?.hasPrefix("multipart/") == true)
        return
    default:
        struct Custom: Decodable, Sendable { let model: String }
        _ = try await c.systemOne(state: "<photo>", questions: ["subject": .box()], assets: ["<photo>": image], responseModel: Custom.self)
    }
    #expect(await mock.requests.first?.headers["content-type"]?.hasPrefix("multipart/") == true)
}

@Test func cancellationBeforeAssetResolutionDoesNotSend() async throws {
    let mock = MockTransport()
    let c = try client(mock)
    let task = Task {
        withUnsafeCurrentTask { $0?.cancel() }
        return try await c.systemOne(state: .image(Image(data: Data([1]))), questions: ["q": .box()])
    }
    await #expect(throws: CancellationError.self) { _ = try await task.value }
    #expect(await mock.requests.isEmpty)
}
