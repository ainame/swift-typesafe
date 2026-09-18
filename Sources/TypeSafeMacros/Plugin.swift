import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxMacros

@main
struct TypeSafePlugin: CompilerPlugin {
    let providingMacros: [any Macro.Type] = [QuestionSetMacro.self, QuestionMarkerMacro.self]
}
