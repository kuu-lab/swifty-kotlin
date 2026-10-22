#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct TrailingDotNumericLiteralTests {
    private func parseDiagnosticCodes(_ source: String) -> [String] {
        let lexed = lex(source)
        let parser = BuildASTPhase.ExpressionParser(
            tokens: lexed.tokens.dropLast(),
            interner: lexed.interner,
            astArena: ASTArena(),
            diagnostics: lexed.diagnostics
        )
        _ = parser.parse()
        return lexed.diagnostics.diagnostics.map(\.code)
    }

    @Test(arguments: ["println(1.)", "1.", "x."])
    func rejectsDotWithoutMember(_ source: String) {
        #expect(parseDiagnosticCodes(source).contains("KSWIFTK-PARSE-0023"))
    }

    @Test(arguments: ["println(.5)", "1.5", "1.toString()", "x.y"])
    func acceptsValidForms(_ source: String) {
        #expect(!parseDiagnosticCodes(source).contains("KSWIFTK-PARSE-0023"))
    }
}
#endif
