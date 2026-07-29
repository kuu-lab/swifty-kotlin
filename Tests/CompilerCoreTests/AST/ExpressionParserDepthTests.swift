#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct ExpressionParserDepthTests {

    @Test("Deeply nested parenthesized expressions report a diagnostic")
    func testDeeplyNestedParenthesizedExpressionReportsDepthDiagnostic() {
        let interner = StringInterner()
        let arena = ASTArena()
        let diagnostics = DiagnosticEngine()
        let depth = BuildASTPhase.ExpressionParser.maxRecursionDepth + 1

        let result = BuildASTPhase.ExpressionParser(
            tokens: makeParenthesizedTokens(depth: depth),
            interner: interner,
            astArena: arena,
            diagnostics: diagnostics
        ).parse()

        #expect(result == nil)
        #expect(diagnostics.diagnostics.contains { $0.code == "KSWIFTK-PARSE-0012" })
    }

    @Test("Parenthesized expressions below the recursion limit still parse")
    func testParenthesizedExpressionBelowDepthLimitParses() {
        let interner = StringInterner()
        let arena = ASTArena()
        let diagnostics = DiagnosticEngine()
        // Each nested expression enters expression, prefix, and primary parsing.
        let depth = (BuildASTPhase.ExpressionParser.maxRecursionDepth / 3) - 1

        let result = BuildASTPhase.ExpressionParser(
            tokens: makeParenthesizedTokens(depth: depth),
            interner: interner,
            astArena: arena,
            diagnostics: diagnostics
        ).parse()

        #expect(result != nil)
        #expect(!diagnostics.diagnostics.contains { $0.code == "KSWIFTK-PARSE-0012" })
    }

    private func makeParenthesizedTokens(depth: Int) -> [Token] {
        var tokens: [Token] = []
        var offset = 0
        for _ in 0..<depth {
            tokens.append(makeToken(kind: .symbol(.lParen), start: offset, end: offset + 1))
            offset += 1
        }
        tokens.append(makeToken(kind: .intLiteral("1"), start: offset, end: offset + 1))
        offset += 1
        for _ in 0..<depth {
            tokens.append(makeToken(kind: .symbol(.rParen), start: offset, end: offset + 1))
            offset += 1
        }
        return tokens
    }
}
#endif
