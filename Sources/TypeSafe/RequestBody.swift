import Foundation
import BasicContainers
import libzstd

/// Compression applies to JSON and multipart bodies at least 1 KiB long.
public enum RequestCompression: Sendable { case zstd, disabled }

/// Immutable segments share image Data storage until compression or transport consumes their bytes.
struct RequestBody: Sendable {
    var segments: [Data]
    var contentType = "application/json"
    var byteCount: Int { segments.reduce(0) { $0 + $1.count } }
    init(data: Data) { segments = [data] }

    func preview(limit: Int = 4096) -> Data {
        var result = Data()
        result.reserveCapacity(min(limit, byteCount))
        for segment in segments {
            result.append(segment.prefix(limit - result.count))
            if result.count == limit { break }
        }
        return result
    }

    mutating func attach(json: Data, images: [(String, Image)]) async throws {
        let boundary = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        var parts: [Data] = []
        func part(_ name: String, type: String, bytes: Data, filename: String? = nil) {
            let file = filename.map { "; filename=\"\($0)\"" } ?? ""
            parts.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\(file)\r\nContent-Type: \(type)\r\n\r\n".utf8))
            parts.append(bytes)
            parts.append(Data("\r\n".utf8))
        }
        part("request", type: "application/json", bytes: json)
        // Aliases of the same image share one resolution within this request. A new request
        // resolves file-backed values again; HTTP retries reuse these prepared segments.
        var resolved: [String: Data] = [:]
        for (index, entry) in images.enumerated() {
            try Task.checkCancellation()
            let bytes: Data
            do {
                if let existing = resolved[entry.1.description] { bytes = existing }
                else {
                    bytes = try await entry.1.resolve()
                    resolved[entry.1.description] = bytes
                }
            }
            catch is CancellationError { throw CancellationError() }
            catch { throw TypeSafeError.configuration("Asset '\(entry.0)': \(error)") }
            let type: String
            if bytes.starts(with: [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]) { type = "image/png" }
            else if bytes.starts(with: [0xff, 0xd8, 0xff]) { type = "image/jpeg" }
            else { type = "application/octet-stream" }
            let name = "asset-\(index)"
            part(name, type: type, bytes: bytes, filename: name)
        }
        parts.append(Data("--\(boundary)--\r\n".utf8))
        segments = parts
        contentType = "multipart/form-data; boundary=\(boundary)"
    }

    consuming func compressed() throws -> Self {
        let compressor = try ZstdCompressor()
        var result = Self(data: try compressor.compress(segments, byteCount: byteCount))
        result.contentType = contentType
        return result
    }
}

/// Owns the C context exactly once; all C pointers are confined to synchronous buffer borrows.
private struct ZstdCompressor: ~Copyable {
    let context: OpaquePointer
    init() throws {
        guard let context = ZSTD_createCCtx() else { throw compressionError() }
        self.context = context
    }
    deinit { ZSTD_freeCCtx(context) }

    func compress(_ segments: borrowing [Data], byteCount: Int) throws -> Data {
        try check(ZSTD_CCtx_setPledgedSrcSize(context, UInt64(byteCount)))
        var result = Data()
        // Capacity is uninitialized; only bytes emitted by zstd are appended.
        result.reserveCapacity(ZSTD_compressBound(byteCount))
        var scratch = RigidArray<UInt8>(capacity: Int(ZSTD_CStreamOutSize()))
        func pump(_ input: inout ZSTD_inBuffer, directive: ZSTD_EndDirective) throws -> Int {
            try Task.checkCancellation()
            scratch.removeAll()
            let remaining = try scratch.edit { span in
                try span.withUnsafeMutableBufferPointer { buffer, initialized in
                    var output = ZSTD_outBuffer(dst: buffer.baseAddress, size: buffer.count, pos: 0)
                    let remaining = ZSTD_compressStream2(context, &output, &input, directive)
                    try check(remaining)
                    initialized = output.pos
                    return remaining
                }
            }
            scratch.span.withUnsafeBufferPointer { bytes in
                if let start = bytes.baseAddress { result.append(start, count: bytes.count) }
            }
            return remaining
        }
        for index in segments.indices {
            try segments[index].withUnsafeBytes { bytes in
                var input = ZSTD_inBuffer(src: bytes.baseAddress, size: bytes.count, pos: 0)
                while input.pos < input.size { _ = try pump(&input, directive: ZSTD_e_continue) }
            }
        }
        var empty = ZSTD_inBuffer(src: nil, size: 0, pos: 0)
        while try pump(&empty, directive: ZSTD_e_end) != 0 {}
        return result
    }
}

private func check(_ result: Int) throws {
    if ZSTD_isError(result) != 0 { throw compressionError() }
}
private func compressionError() -> TypeSafeError { .encoding("The request body could not be compressed with zstd.") }
