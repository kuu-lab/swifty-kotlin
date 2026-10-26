#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct EmptyStringTemplateParsingTests {
    @Test(arguments: [#""${}""#, #""${ }""#, "\"\"\"${}\"\"\"", #""${"${}"}""#])
    func emptyTemplateExpressionIsRejected(_ source: String) {
        let lexed = lex(source)
        let arena = ASTArena()
        let parser = BuildASTPhase.ExpressionParser(
            tokens: lexed.tokens.dropLast(),
            interner: lexed.interner,
            astArena: arena,
            diagnostics: lexed.diagnostics
        )

        _ = parser.parse()
        #expect(lexed.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-PARSE-0004" })
    }

    @Test(arguments: [#""$""#, #""$x""#, #""${x}""#, #""a${x}b""#])
    func nonEmptyTemplateFormsStayAccepted(_ source: String) {
        let lexed = lex(source)
        let arena = ASTArena()
        let parser = BuildASTPhase.ExpressionParser(
            tokens: lexed.tokens.dropLast(),
            interner: lexed.interner,
            astArena: arena,
            diagnostics: lexed.diagnostics
        )

        #expect(parser.parse() != nil)
        #expect(!lexed.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-PARSE-0004" })
    }
}
#endif
