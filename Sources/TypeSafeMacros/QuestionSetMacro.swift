import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

private struct MacroError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

public struct QuestionMarkerMacro: PeerMacro {
    public static func expansion(of node: AttributeSyntax, providingPeersOf declaration: some DeclSyntaxProtocol, in context: some MacroExpansionContext) throws -> [DeclSyntax] {
        guard declaration.is(VariableDeclSyntax.self) else { throw MacroError("Question markers can only be applied to properties in a @QuestionSet struct.") }
        guard context.lexicalContext.contains(where: { syntax in
            guard let type = syntax.as(StructDeclSyntax.self) else { return false }
            return type.attributes.contains { attribute in
                attribute.as(AttributeSyntax.self)?.attributeName.trimmedDescription.split(separator: ".").last == "QuestionSet"
            }
        }) else { throw MacroError("Question markers require an enclosing @QuestionSet struct.") }
        return []
    }
}

public struct QuestionSetMacro: MemberMacro, ExtensionMacro {
    public static func expansion(of node: AttributeSyntax, providingMembersOf declaration: some DeclGroupSyntax, conformingTo protocols: [TypeSyntax], in context: some MacroExpansionContext) throws -> [DeclSyntax] {
        guard let type = declaration.as(StructDeclSyntax.self), type.genericParameterClause == nil else {
            throw MacroError("@QuestionSet requires a non-generic struct.")
        }
        let access = type.modifiers.contains { $0.name.tokenKind == .keyword(.public) } ? "public " : ""
        var questions: [String] = []
        var fields: [String] = []
        var initializers: [String] = []
        for member in type.memberBlock.members {
            if let nested = member.decl.as(StructDeclSyntax.self), nested.name.text == "Answers" {
                throw MacroError("Answers is reserved for @QuestionSet generated code.")
            }
            if let function = member.decl.as(FunctionDeclSyntax.self), function.name.text == "decodeAnswers" {
                throw MacroError("decodeAnswers is reserved for @QuestionSet generated code.")
            }
            guard let variable = member.decl.as(VariableDeclSyntax.self) else { continue }
            let markers = variable.attributes.compactMap { $0.as(AttributeSyntax.self) }.filter {
                ["Choice", "Noul", "Score"].contains($0.attributeName.trimmedDescription.split(separator: ".").last.map(String.init) ?? "")
            }
            let isStatic = variable.modifiers.contains { ["static", "class"].contains($0.name.text) }
            if markers.isEmpty {
                if variable.bindings.contains(where: { $0.pattern.trimmedDescription == "questions" }) {
                    throw MacroError("questions is reserved for @QuestionSet generated code.")
                }
                if !isStatic, variable.bindings.contains(where: { $0.accessorBlock == nil }) {
                    throw MacroError("Every stored property in @QuestionSet must have a @Choice, @Noul, or @Score marker.")
                }
                continue
            }
            guard markers.count == 1, variable.bindings.count == 1, let binding = variable.bindings.first,
                  let identifier = binding.pattern.as(IdentifierPatternSyntax.self), let annotation = binding.typeAnnotation,
                  binding.accessorBlock == nil, binding.initializer == nil, !isStatic else {
                throw MacroError("Declare one non-static stored question property with an explicit type and no initializer.")
            }
            let property = identifier.identifier.trimmedDescription
            let name = String(identifier.identifier.text.filter { $0 != "`" })
            guard !["questions", "Answers", "decodeAnswers"].contains(name) else {
                throw MacroError("\(name) is reserved for @QuestionSet generated code.")
            }
            let marker = markers[0]
            let kind = String(marker.attributeName.trimmedDescription.split(separator: ".").last!)
            let valueType = annotation.type.trimmedDescription
            if kind != "Choice", !["Double", "Swift.Double"].contains(valueType) {
                throw MacroError("@\(kind) properties must have type Double.")
            }
            let arguments: LabeledExprListSyntax
            if case .argumentList(let list) = marker.arguments { arguments = list } else { arguments = [] }
            let instructions = arguments.first(where: { $0.label == nil })?.expression.trimmedDescription ?? "nil"
            let criteria = arguments.first(where: { $0.label?.text == "criteria" })?.expression.trimmedDescription
            let question: String
            let answerType: String
            let decode: String
            switch kind {
            case "Choice":
                question = ".choice(instructions: \(instructions), criteria: TypeSafe.choiceCriteria(for: \(valueType).self, descriptions: \(criteria ?? "nil")))"
                answerType = "TypeSafe.ChoiceAnswer<\(valueType)>"
                decode = "try response.choice(named: \(String(reflecting: name)), as: \(valueType).self)"
            case "Score":
                guard let criteria else { throw MacroError("@Score requires an ordered criteria array.") }
                question = ".score(instructions: \(instructions), criteria: \(criteria))"
                answerType = "TypeSafe.ScoreAnswer"
                decode = "try response.score(named: \(String(reflecting: name)))"
            default:
                question = ".noul(instructions: \(instructions), criteria: \(criteria ?? "nil"))"
                answerType = "TypeSafe.NoulAnswer"
                decode = "try response.noul(named: \(String(reflecting: name)))"
            }
            questions.append("\(String(reflecting: name)): \(question)")
            fields.append("\(access)let \(property): \(answerType)")
            initializers.append("\(property): \(decode)")
        }
        guard !questions.isEmpty else { throw MacroError("@QuestionSet requires at least one question property.") }
        return [
            DeclSyntax(stringLiteral: "\(access)static var questions: [String: TypeSafe.Question] { [\(questions.joined(separator: ",\n"))] }"),
            DeclSyntax(stringLiteral: "\(access)struct Answers: Sendable { \(fields.joined(separator: "\n")) }"),
            DeclSyntax(stringLiteral: "\(access)static func decodeAnswers(from response: TypeSafe.SystemOneResponse) throws -> Answers { Answers(\(initializers.joined(separator: ",\n"))) }")
        ]
    }

    public static func expansion(of node: AttributeSyntax, attachedTo declaration: some DeclGroupSyntax, providingExtensionsOf type: some TypeSyntaxProtocol, conformingTo protocols: [TypeSyntax], in context: some MacroExpansionContext) throws -> [ExtensionDeclSyntax] {
        guard declaration.is(StructDeclSyntax.self) else { return [] }
        return [try ExtensionDeclSyntax("extension \(type): TypeSafe.QuestionSet {}")]
    }
}
