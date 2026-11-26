@testable import CompilerCore
import Foundation

func lex(
    _ source: String,
    interner: StringInterner = StringInterner(),
    diagnostics: DiagnosticEngine = DiagnosticEngine()
) -> (tokens: [Token], interner: StringInterner, diagnostics: DiagnosticEngine) {
    let lexer = KotlinLexer(
        file: FileID(rawValue: 0),
        source: Data(source.utf8),
        interner: interner,
        diagnostics: diagnostics
    )
    return (lexer.lexAll(), interner, diagnostics)
}

func parse(
    _ source: String,
    interner: StringInterner = StringInterner(),
    diagnostics: DiagnosticEngine = DiagnosticEngine()
) -> (arena: SyntaxArena, root: NodeID, diagnostics: DiagnosticEngine, interner: StringInterner, tokens: [Token]) {
    let lexed = lex(source, interner: interner, diagnostics: diagnostics)
    let parser = KotlinParser(tokens: lexed.tokens, interner: lexed.interner, diagnostics: lexed.diagnostics)
    let parsed = parser.parseFile()
    return (parsed.arena, parsed.root, lexed.diagnostics, lexed.interner, lexed.tokens)
}

func charValues(in tokens: [Token]) -> [UInt32] {
    tokens.compactMap { token in
        guard case let .charLiteral(value) = token.kind else { return nil }
        return value
    }
}
