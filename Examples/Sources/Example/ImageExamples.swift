import Foundation
import TypeSafe

@QuestionSet
private struct ImageQuestions {
    @Box("The red square in the center") var square: BoxCoordinates
    @Noul("Is there a red square on a white background?") var red: Double
}

private struct CheckError: Error { let message: String }
private func check(_ box: BoxCoordinates) throws {
    let values = [box.top, box.bottom, box.left, box.right]
    guard values.allSatisfy({ $0.isFinite && (0...1).contains($0) }), box.top < box.bottom, box.left < box.right else {
        throw CheckError(message: "Invalid bounds: \(box)")
    }
    // The 512×512 fixture has a red square spanning pixels [128, 384) on white.
    // Allow model variation around its known normalized bounds.
    let error = zip(values, [0.25, 0.75, 0.25, 0.75]).map { abs($0 - $1) }.max()!
    print("bounds=\(box) maxEdgeError=\(error)")
    guard error < 0.12 else { throw CheckError(message: "Bounds miss known square") }
}

func runImageExamples() async throws {
    guard let url = Bundle.module.url(forResource: "centered-red-square", withExtension: "png", subdirectory: "Fixtures") else {
        throw CheckError(message: "Bundled image fixture is missing")
    }
    let data = try Data(contentsOf: url)
    for (name, compression) in [("zstd", RequestCompression.zstd), ("uncompressed", .disabled)] {
        let client = try TypeSafeClient(model: "jev-1.14.0", timeout: 120, retry: .init(maxRetries: 0),
            headers: ["TypeSafe-Danger-Zone-Images": "true"], compression: compression)
        print("START \(name) loaded Data + builder")
        let loaded = try await client.systemOne(state: Image(data: data)) {
            Box("The red square in the center")
            Noul("Is there a red square on a white background?")
        }
        try check(loaded.answers.0.box)
        guard loaded.answers.1.noul > 0.5 else { throw CheckError(message: "Image recognition failed") }
        print("red=\(loaded.answers.1.noul) requestID=\(loaded.requestID ?? "none")")
        print("START \(name) file + macro")
        let file = Image(fileURL: url)
        let macro = try await client.systemOne(state: file, questions: ImageQuestions.self)
        try check(macro.answers.square.box)
        guard macro.answers.red.noul > 0.5 else { throw CheckError(message: "File recognition failed") }
        print("red=\(macro.answers.red.noul) requestID=\(macro.requestID ?? "none")")
        print("START \(name) scoped reference + dynamic")
        let attached = try await client.withAttachedAssets([file]) {
            try await client.systemOne(state: .string("Inspect \(file)"), questions: ["square": .box(instructions: "The red square in the center")])
        }
        try check(try attached.box(named: "square").box)
        print("requestID=\(attached.requestID ?? "none")")
    }
    print("PASS all six live image requests")
}
