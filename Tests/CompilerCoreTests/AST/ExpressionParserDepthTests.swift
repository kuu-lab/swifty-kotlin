#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct ExpressionParserDepthTests {

    @Test("Deeply nested parenthesized expressions report a diagnostic")
    func testDeeplyNestedParenthesizedExpressionReportsDepthDiagnostic() {
        let (result, diagnostics) = parseParenthesized(
            depth: BuildASTPhase.ExpressionParser.maxRecursionDepth + 1
        )

        #expect(result == nil)
        #expect(diagnostics.diagnostics.contains { $0.code == "KSWIFTK-PARSE-0012" })
    }

    @Test("Parenthesized expressions below the recursion limit still parse")
    func testParenthesizedExpressionBelowDepthLimitParses() {
        // Each nested expression enters expression, prefix, and primary parsing.
        let (result, diagnostics) = parseParenthesized(
            depth: (BuildASTPhase.ExpressionParser.maxRecursionDepth / 3) - 1
        )

        #expect(result != nil)
        #expect(!diagnostics.diagnostics.contains { $0.code == "KSWIFTK-PARSE-0012" })
    }

    private func parseParenthesized(depth: Int) -> (result: ExprID?, diagnostics: DiagnosticEngine) {
        let diagnostics = DiagnosticEngine()
        let result = BuildASTPhase.ExpressionParser(
            tokens: makeParenthesizedTokens(depth: depth),
            interner: StringInterner(),
            astArena: ASTArena(),
            diagnostics: diagnostics
        ).parse()
        return (result, diagnostics)
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
