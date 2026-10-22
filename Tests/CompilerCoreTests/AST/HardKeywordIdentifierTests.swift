#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct HardKeywordIdentifierTests {
    @Test(arguments: [Keyword.class, .fun, .when, .as, .in, .is])
    func hardKeywordsAreNotSimpleIdentifierNames(_ keyword: Keyword) {
        let kind = TokenKind.keyword(keyword)
        #expect(!kind.isLabelName)
        #expect(!TypeRefParserCore.isDeclarationNameToken(kind))
        #expect(!TypeRefParserCore.isTypeLikeNameToken(kind))
    }

    @Test(arguments: [Keyword.class, .fun, .when])
    func bareHardKeywordDoesNotParseAsANameReference(_ keyword: Keyword) {
        let result = lex(keyword.rawValue)
        let parser = BuildASTPhase.ExpressionParser(
            tokens: result.tokens.dropLast(),
            interner: result.interner,
            astArena: ASTArena(),
            diagnostics: result.diagnostics
        )

        #expect(parser.parse() == nil)
    }

    @Test(arguments: ["class", "fun", "when"])
    func localVariableRequiresBackticks(_ keyword: String) throws {
        try withTemporaryFile(contents: "fun main() { val \(keyword) = 5 }") { path in
            let context = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(context)

            #expect(context.diagnostics.hasError, "Expected unquoted hard keyword '\(keyword)' to be rejected")
        }
    }

    @Test
    func backtickedHardKeywordsRemainLegalVariableNames() throws {
        let source = """
        fun main(): Int {
            val `class` = 5
            val `fun` = 1
            val `when` = 3
            return `class` + `fun` + `when`
        }
        """
        try withTemporaryFile(contents: source) { path in
            let context = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(context)

            #expect(!context.diagnostics.hasError, "Backticked hard keywords should remain valid: \(context.diagnostics.diagnostics)")
        }
    }
}
#endif
