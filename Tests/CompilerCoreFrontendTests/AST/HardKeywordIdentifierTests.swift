#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

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

    /// KUU-4363: `import` is a hard keyword token, but Kotlin only treats it
    /// as a directive at compilation-unit level. Inside blocks it remains a
    /// legal simple identifier — kotlinc accepts it as a local name, a
    /// value-parameter name and a lambda parameter.
    @Test
    func importIsLegalIdentifierInsideBlocks() throws {
        let source = """
        fun apply(f: (Int) -> Int, v: Int): Int = f(v)
        fun named(import: Int): Int = import + 1
        fun main(): Int {
            val import = 20
            val g: (Int) -> Int = { import -> import + 1 }
            return import + named(import) + apply({ x -> x * 2 }, 3) + g(1)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let context = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(context)

            #expect(!context.diagnostics.hasError, "Expected 'import' to stay usable as an identifier inside blocks: \(context.diagnostics.diagnostics)")
        }
    }

    /// KUU-4363 guard: removing `import` from the declaration-start keywords
    /// must not break real import directives at file top level.
    @Test
    func topLevelImportRemainsAnImportDirective() throws {
        let (ast, ctx) = try buildASTModule(from: """
        import kotlin.collections.listOf
        fun main() = 0
        """, includeStdlib: false)

        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let file = try #require(ast.files.first)
        #expect(file.imports.count == 1)
        #expect(file.topLevelDecls.count == 1)
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
