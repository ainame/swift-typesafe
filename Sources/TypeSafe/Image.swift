import Foundation

/// An image value backed by bytes or a file URL.
/// Use `.image(photo)` anywhere in state, instructions, or criteria, or interpolate `photo`
/// into text inside `withAttachedAssets`.
/// File-backed values are read for each new request. To reuse fixed bytes across requests,
/// load the file yourself and use `Image(data:)`. HTTP retries reuse the prepared request body.
public struct Image: Sendable, Equatable, CustomStringConvertible {
    private enum Source: Sendable {
        case data(Data)
        case file(URL)
    }
    private let source: Source
    public let description = "<image:\(UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased())>"

    public init(data: Data) { source = .data(data) }
    public init(fileURL: URL) { source = .file(fileURL) }

    public static func fromBase64(_ text: String) throws -> Image {
        guard text.unicodeScalars.allSatisfy({ $0.isASCII }) else {
            throw TypeSafeError.configuration("Image data must contain non-empty ASCII base64 text.")
        }
        let clean = text.filter { !$0.isWhitespace }
        guard !clean.isEmpty, let data = Data(base64Encoded: clean) else {
            throw TypeSafeError.configuration("Image data must contain valid non-empty base64 text.")
        }
        return Image(data: data)
    }

    // Copies retain the same asset reference; separately constructed values are distinct assets.
    public static func == (lhs: Image, rhs: Image) -> Bool { lhs.description == rhs.description }

    @concurrent func resolve() async throws -> Data {
        try Task.checkCancellation()
        let bytes: Data
        switch source {
        case .data(let data): bytes = data
        case .file(let url):
            guard url.isFileURL else { throw TypeSafeError.configuration("Image URL must be a local file URL.") }
            // No shared cache: each request reads the current file contents. This synchronous
            // read occupies a cooperative-pool thread; @concurrent keeps it off the caller's actor.
            do { bytes = try Data(contentsOf: url) }
            catch { throw TypeSafeError.configuration("Image file could not be read: \(error.localizedDescription)") }
        }
        try Task.checkCancellation()
        guard !bytes.isEmpty else { throw TypeSafeError.configuration("Image data is empty.") }
        return bytes
    }
}

/// Shared by copies of a client, matching upstream attachment visibility across concurrent calls.
actor AttachedImages {
    private struct Entry { let image: Image; var count: Int }
    private var entries: [String: Entry] = [:]
    func add(_ images: [Image]) {
        for image in images {
            let key = image.description
            if entries[key] == nil { entries[key] = Entry(image: image, count: 0) }
            entries[key]!.count += 1
        }
    }
    func remove(_ images: [Image]) {
        for image in images {
            let key = image.description
            entries[key]!.count -= 1
            if entries[key]!.count == 0 { entries.removeValue(forKey: key) }
        }
    }
    var snapshot: [String: Image] { entries.mapValues(\.image) }
}

extension TypeSafeClient {
    /// Keeps images available by their interpolated references for the duration of the operation.
    /// Overlapping scopes can attach the same image; it remains available until the last scope ends.
    public nonisolated(nonsending) func withAttachedAssets<Result>(
        _ images: [Image], operation: () async throws -> Result
    ) async rethrows -> Result {
        await attachedImages.add(images)
        do {
            let result = try await operation()
            await attachedImages.remove(images)
            return result
        } catch {
            await attachedImages.remove(images)
            throw error
        }
    }
}
