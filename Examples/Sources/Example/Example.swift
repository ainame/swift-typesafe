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
        print(try await client.models.list().models)
    }
}
