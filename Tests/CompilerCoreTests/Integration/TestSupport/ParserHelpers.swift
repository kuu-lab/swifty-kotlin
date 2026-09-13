@testable import CompilerCore
import Foundation

/// Lexes `source` as a single anonymous file, returning the token stream along
/// with the interner and diagnostic engine the lexer wrote into.
func lex(_ source: String) -> (tokens: [Token], interner: StringInterner, diagnostics: DiagnosticEngine) {
    let diagnostics = DiagnosticEngine()
    let interner = StringInterner()
    let lexer = KotlinLexer(
        file: FileID(rawValue: 0),
        source: Data(source.utf8),
        interner: interner,
        diagnostics: diagnostics
    )
    return (lexer.lexAll(), interner, diagnostics)
}

/// Lexes and parses `source` into a CST, returning the arena and root node
/// alongside the interner, diagnostics and tokens they refer to.
func parse(_ source: String) -> (arena: SyntaxArena, root: NodeID, diagnostics: DiagnosticEngine, interner: StringInterner, tokens: [Token]) {
    let lexed = lex(source)
    let parser = KotlinParser(tokens: lexed.tokens, interner: lexed.interner, diagnostics: lexed.diagnostics)
    let parsed = parser.parseFile()
    return (parsed.arena, parsed.root, lexed.diagnostics, lexed.interner, lexed.tokens)
}
