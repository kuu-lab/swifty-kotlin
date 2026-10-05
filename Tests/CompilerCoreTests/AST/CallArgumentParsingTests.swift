#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct CallArgumentParsingTests {
    @Test(arguments: [
        "f(1 2)", "f(1b)", "f(1c)", "f(1x)", "f(1z)",
        "f(\"x\" y)", "f(a b)", "f(1b, 2)", "listOf(1, 2 z)",
        "println(listOf(1b))", "println(listOf(1b).size)",
        "obj.f(1 2)", "obj?.f(1b)", "f<Int>(1b)", "obj.f<Int>(1b)",
        "f(value = 1 2)", "f(*items other)", "f(1\n2)",
    ])
    func rejectsMissingArgumentSeparator(_ source: String) throws {
        let lexed = lex(source)
        let parser = BuildASTPhase.ExpressionParser(
            tokens: lexed.tokens.dropLast(),
            interner: lexed.interner,
            astArena: ASTArena(),
            diagnostics: lexed.diagnostics
        )
        _ = parser.parse()

        let diagnostic = try #require(lexed.diagnostics.diagnostics.first {
            $0.code == "KSWIFTK-PARSE-0015"
        })
        #expect(diagnostic.severity == .error)
        #expect(diagnostic.message == "Expected ',' or ')' after call argument.")
    }

    @Test(arguments: [
        "f()", "f(1)", "f(1, 2)", "f(1,)", "f(1,\n2,\n)",
        "f(value = 1, other = 2)", "f(*items, 2)", "f(1 + 2)",
        "f(a to b)", "f(1L, 2u, 3UL, 4f)", "f(g(1, 2).size, 3)",
        "obj?.f<Int>(1, 2)", "f(1) { 2 }", "f({ 1 }, ({ 2 }))",
    ])
    func acceptsValidArguments(_ source: String) throws {
        let lexed = lex(source)
        let parser = BuildASTPhase.ExpressionParser(
            tokens: lexed.tokens.dropLast(),
            interner: lexed.interner,
            astArena: ASTArena(),
            diagnostics: lexed.diagnostics
        )
        #expect(parser.parse() != nil)
        #expect(lexed.diagnostics.diagnostics.isEmpty)
        #expect(parser.current() == nil)
    }

    @Test(arguments: [
        "fun main() { println(1 2) }",
        "fun main() { println(1b) }",
        "fun main() { println(\"x\" y) }",
        "fun main() { val a = 7; println(a b) }",
        "fun main() { println(listOf(1b).size) }",
        "fun main() { val xs = listOf(1, 2 z) }",
        "fun value() = f(1b)",
        "val value = f(1b)",
        "fun main() { val block = { f(1b) } }",
        "fun main() { var x = 0; when (0) { else -> x = f(1b) } }",
    ])
    func frontendReportsMissingSeparator(_ source: String) throws {
        let (_, context) = try buildASTModule(from: source, includeStdlib: false)
        #expect(context.diagnostics.diagnostics.contains {
            $0.code == "KSWIFTK-PARSE-0015" && $0.severity == .error
        })
    }

    @Test
    func diagnosticPointsToUnexpectedToken() throws {
        let lexed = lex("f(1 2)")
        let parser = BuildASTPhase.ExpressionParser(
            tokens: lexed.tokens.dropLast(),
            interner: lexed.interner,
            astArena: ASTArena(),
            diagnostics: lexed.diagnostics
        )
        _ = parser.parse()
        let diagnostic = try #require(lexed.diagnostics.diagnostics.first)
        #expect(diagnostic.primaryRange?.start.offset == 4)
        #expect(diagnostic.primaryRange?.end.offset == 5)
    }
}
#endif
