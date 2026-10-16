import Foundation
import Testing
import libzstd
@testable import TypeSafe

private let imageFixture = #"{"model":"jev-preview","usage":{},"answers":{"subject":{"type":"box","box":{"top":0.1,"bottom":0.9,"left":0.2,"right":0.8},"confidence":null}}}"#

@QuestionSet
private struct LoadedImageQuestions {
    @Box("The subject") var subject: BoxCoordinates
}

@Test(arguments: ["dynamic", "macro", "builder", "custom"], ["data", "file", "base64"])
func imagesReachEveryClientAPI(api: String, source: String) async throws {
    let data = Data([0xff, 0xd8, 0xff, 0, 255])
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: url) }
    let image: Image
    switch source {
    case "file":
        try data.write(to: url)
        image = Image(fileURL: url)
    case "base64": image = try Image.fromBase64(data.base64EncodedString())
    default: image = Image(data: data)
    }
    let fixture = api == "builder" ? imageFixture.replacingOccurrences(of: "subject", with: "question_0") : imageFixture
    let mock = MockTransport { _, _ in response(fixture) }
    let c = try TypeSafeClient(apiKey: "k", compression: .disabled, transport: mock, environment: [:])
    switch api {
    case "macro":
        let result = try await c.systemOne(state: image, questions: LoadedImageQuestions.self, model: "jev-preview")
        #expect(result.answers.subject.box.top == 0.1)
    case "builder":
        let result = try await c.systemOne(state: image, model: "jev-preview") { Box("The subject") }
        #expect(result.answers.box.top == 0.1)
    case "custom":
        struct Custom: Decodable, Sendable { let model: String }
        let result = try await c.systemOne(state: image, questions: ["subject": .box()], responseModel: Custom.self)
        #expect(result.model == "jev-preview")
    default:
        let result = try await c.systemOne(state: image, questions: ["subject": .box()])
        #expect(result.boxes["subject"]?.box.top == 0.1)
    }
    let request = try #require(await mock.requests.first)
    #expect(request.headers["content-type"]?.hasPrefix("multipart/form-data;") == true)
    #expect(request.bodySegments?.contains(data) == true)
    #expect(request.body?.range(of: Data(image.description.utf8)) != nil)
    #expect(request.body?.range(of: data) != nil)
}

@Test func loadedDataWorksInsideStructuredContent() async throws {
    let data = Data([1, 2, 3, 255])
    let mock = MockTransport()
    let c = try TypeSafeClient(apiKey: "k", compression: .disabled, transport: mock, environment: [:])
    _ = try await c.systemOne(state: ["photo": .image(data)], questions: ["q": .choice(instructions: .image(data), criteria: ["a": .image(data)])])
    let request = try #require(await mock.requests.first)
    #expect(request.bodySegments?.filter { $0 == data }.count == 3)
}

@Test func emptyImageFailsBeforeNetwork() async throws {
    let mock = MockTransport()
    await #expect(throws: TypeSafeError.self) {
        _ = try await client(mock).systemOne(state: Image(data: Data()), questions: ["subject": .box()])
    }
    #expect(await mock.requests.isEmpty)
}

@Test func multipartRetainsImageStorageAndBoundsLogPreview() async throws {
    let bytes = Data(repeating: 42, count: 2 * 1024 * 1024)
    var body = RequestBody(data: Data())
    try await body.attach(json: Data("{}".utf8), images: [("photo", Image(data: bytes))])
    let segment = try #require(body.segments.first { $0.count == bytes.count })
    bytes.withUnsafeBytes { original in
        segment.withUnsafeBytes { shared in
            #expect(original.baseAddress == shared.baseAddress)
        }
    }
    #expect(body.preview().count == 4096)
    #expect(body.byteCount > bytes.count)
    let compressed = try body.compressed()
    #expect(compressed.segments.count == 1)
    #expect(compressed.contentType == body.contentType)
    let restored = try decodeZstd(#require(compressed.segments.first))
    #expect(restored == body.segments.reduce(into: Data()) { $0.append($1) })
}

@Test func streamingCompressionHandlesEmptyAndIncompressibleSegments() throws {
    var value: UInt64 = 0x123456789abcdef
    let random = Data((0..<(1024 * 1024)).map { _ in
        value ^= value << 13; value ^= value >> 7; value ^= value << 17
        return UInt8(truncatingIfNeeded: value)
    })
    var body = RequestBody(data: Data())
    body.segments = [Data(), random.prefix(123), Data(), random.dropFirst(123), Data()]
    #expect(try decodeZstd(#require(body.compressed().segments.first)) == random)
    #expect(try decodeZstd(#require(RequestBody(data: Data()).compressed().segments.first)).isEmpty)
}

@Test func segmentedMultipartRetriesReuseThePreparedBody() async throws {
    let mock = MockTransport { _, attempt in
        attempt == 1 ? response("{}", status: 429, headers: ["retry-after-ms": "0"]) : response(imageFixture)
    }
    let c = try TypeSafeClient(apiKey: "k", retry: .init(maxRetries: 1), compression: .disabled, transport: mock, environment: [:])
    _ = try await c.systemOne(state: Image(data: Data(repeating: 1, count: 128 * 1024)), questions: ["subject": .box()])
    let requests = await mock.requests
    #expect(requests.count == 2)
    #expect(requests[0].bodySegments == requests[1].bodySegments)
    #expect(requests[1].headers["x-typesafe-retry-count"] == "1")
}

private func decodeZstd(_ data: Data) throws -> Data {
    let size = data.withUnsafeBytes { ZSTD_getFrameContentSize($0.baseAddress, $0.count) }
    try #require(size <= 4 * 1024 * 1024)
    var result = Data(count: Int(size))
    let count = result.withUnsafeMutableBytes { output in
        data.withUnsafeBytes { input in ZSTD_decompress(output.baseAddress, output.count, input.baseAddress, input.count) }
    }
    try #require(ZSTD_isError(count) == 0)
    result.count = count
    return result
}
