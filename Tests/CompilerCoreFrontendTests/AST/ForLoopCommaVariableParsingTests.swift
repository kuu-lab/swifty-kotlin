#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct ForLoopCommaVariableParsingTests {
    @Test(arguments: [
        "for (i, j in x) { }",
        "for (i, j, k in x) { }",
        "for (i, in x) { }",
        "for (i: Int, j in x) { }",
        "for (i: Map<K, V>, j in x) { }",
    ])
    func rejectsCommaSeparatedLoopVariables(_ source: String) throws {
        let lexed = lex(source)
        let parser = BuildASTPhase.ExpressionParser(
            tokens: lexed.tokens.dropLast(),
            interner: lexed.interner,
            astArena: ASTArena(),
            diagnostics: lexed.diagnostics
        )

        _ = parser.parse()

        #expect(lexed.diagnostics.diagnostics.contains {
            $0.severity == .error
                && $0.code == "KSWIFTK-PARSE-0004"
                && $0.message == "Unexpected ',' in 'for' loop header."
        })
    }

    @Test(arguments: [
        "for (i in x) { }",
        "for ((i, j) in x) { }",
        "for ((i, j, k) in x) { }",
        "for (i: Int in x) { }",
        "for (m: Map<K, V> in x) { }",
        "for (m: Map<K, List<V>> in x) { }",
    ])
    func acceptsValidLoopHeaders(_ source: String) throws {
        let lexed = lex(source)
        let parser = BuildASTPhase.ExpressionParser(
            tokens: lexed.tokens.dropLast(),
            interner: lexed.interner,
            astArena: ASTArena(),
            diagnostics: lexed.diagnostics
        )

        #expect(parser.parse() != nil)
        #expect(lexed.diagnostics.diagnostics.isEmpty)
    }
}
#endif
