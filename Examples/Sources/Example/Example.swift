import Foundation
import TypeSafe

enum Category: String, CaseIterable, Codable, Sendable { case billing, technical, other }

@QuestionSet
struct TicketQuestions {
    @Choice("What is this ticket about?") var category: Category
    @Noul("Does this need urgent attention?") var urgent: Double
    @Score("How severe is this issue?", criteria: ["minor", "moderate", "severe"]) var severity: Double
}

@main struct Example {
    static func main() async throws {
        let client = try TypeSafeClient()
        let response = try await client.systemOne(state: "I was charged twice.", questions: TicketQuestions.self)
        print(response.answers.category.choice)
        print(response.answers.urgent.noul)
        print(response.answers.severity.score)

        let (category, urgent, severity) = try await client.systemOne(state: "I was charged twice.") {
            Choice<Category>("What is this ticket about?")
            Noul("Does this need urgent attention?")
            Score("How severe is this issue?", criteria: ["minor", "moderate", "severe"])
        }.answers
        print(category.choice)
        print(urgent.noul)
        print(severity.score)

        let shouldReply = try await client.systemOne(state: "I was charged twice.") {
            Noul("Should customer support reply?")
        }
        print(shouldReply.answers.noul)
        print(shouldReply.usage)
        print(shouldReply.requestID as Any)
        print(try await client.models.list().models)
    }
}


@QuestionSet
struct PhotoQuestions {
    @Box("The product") var product: BoxCoordinates
}

// Compile the image APIs without requiring an image file or spending production credits at startup.
func inspectPhoto(client: TypeSafeClient, fileURL: URL) async throws -> BoxCoordinates {
    let photo = Image(fileURL: fileURL)
    let located = try await client.systemOne(state: photo, questions: PhotoQuestions.self, model: "jev-preview")
    _ = try await client.withAttachedAssets([photo]) {
        try await client.systemOne(state: .string("Inspect \(photo)")) { Noul("Is the product damaged?") }
    }
    return located.answers.product.box
}

// The same image state API accepts images constructed from bytes, files, or base64.
func locateProduct(client: TypeSafeClient, imageData: Data) async throws -> BoxCoordinates {
    let located = try await client.systemOne(state: Image(data: imageData), model: "jev-preview") { Box("The product") }
    return located.answers.box
}
