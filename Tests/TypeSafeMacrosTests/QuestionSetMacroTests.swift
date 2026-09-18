import Testing
import SwiftSyntaxMacroExpansion
import SwiftSyntaxMacrosGenericTestSupport
import TypeSafeMacros

@Test func generatesConcreteResponseAndRequestSchema() {
    assertMacroExpansion(
        """
        @QuestionSet
        struct Questions {
            @Noul("Ready?") var ready: Double
        }
        """,
        expandedSource: """
        struct Questions {
            var ready: Double

            static var questions: [String: TypeSafe.Question] {
                ["ready": .noul(instructions: "Ready?", criteria: nil)]
            }

            struct Answers: Sendable {
                let ready: TypeSafe.NoulAnswer
            }

            static func decodeAnswers(from response: TypeSafe.SystemOneResponse) throws -> Answers {
                Answers(ready: try response.noul(named: "ready"))
            }
        }

        extension Questions: TypeSafe.QuestionSet {
        }
        """,
        macroSpecs: [
            "QuestionSet": MacroSpec(type: QuestionSetMacro.self, conformances: ["QuestionSet"]),
            "Noul": MacroSpec(type: QuestionMarkerMacro.self),
        ],
        failureHandler: { Issue.record(Comment(rawValue: $0.message)) }
    )
}

@Test func rejectsUnsupportedDeclaration() {
    assertMacroExpansion(
        """
        @QuestionSet
        class Questions {}
        """,
        expandedSource: "class Questions {}",
        diagnostics: [DiagnosticSpec(message: "@QuestionSet requires a non-generic struct.", line: 1, column: 1)],
        macroSpecs: ["QuestionSet": MacroSpec(type: QuestionSetMacro.self)],
        failureHandler: { Issue.record(Comment(rawValue: $0.message)) }
    )
}

@Test func markerRequiresSchema() {
    assertMacroExpansion(
        """
        struct Questions {
            @Noul var ready: Double
        }
        """,
        expandedSource: """
        struct Questions {
            var ready: Double
        }
        """,
        diagnostics: [DiagnosticSpec(message: "Question markers require an enclosing @QuestionSet struct.", line: 2, column: 5)],
        macroSpecs: ["Noul": MacroSpec(type: QuestionMarkerMacro.self)],
        failureHandler: { Issue.record(Comment(rawValue: $0.message)) }
    )
}
