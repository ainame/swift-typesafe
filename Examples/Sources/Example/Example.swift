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
