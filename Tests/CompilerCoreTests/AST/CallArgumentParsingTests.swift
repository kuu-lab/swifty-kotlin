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
        "f(,1)", "f(1,,2)", "f(,)", "f(,,)", "f(1,,)",
        "f(x = ,1)", "f(x = )", "f(*)", "f(*,)", "f(,,1)",
        "obj.f(,1)", "obj?.f(,1)", "f<Int>(,1)", "println(f(,1))",
        "g(f(,1), 2)",
    ])
    func rejectsEmptyArgumentElement(_ source: String) throws {
        let lexed = lex(source)
        let parser = BuildASTPhase.ExpressionParser(
            tokens: lexed.tokens.dropLast(),
            interner: lexed.interner,
            astArena: ASTArena(),
            diagnostics: lexed.diagnostics
        )
        _ = parser.parse()

        let diagnostic = try #require(lexed.diagnostics.diagnostics.first {
            $0.code == "KSWIFTK-PARSE-0022"
        })
        #expect(diagnostic.severity == .error)
        #expect(diagnostic.message == "Expected an argument.")
    }

    @Test(arguments: [
        "fun main() { println(f(,1)) }",
        "fun main() { val v = f(1,,2) }",
        "fun main() { println(obj.f(,1)) }",
        "fun f(x: Int) = x\nfun main() { println(f(x = ,1)) }",
        "enum class E(val x: Int) { A(,1) }",
        "open class Base(x: Int)\nclass C : Base(,1)",
        "open class Base(x: Int, y: Int)\nclass C : Base(1,,2)",
        "open class Base()\nclass C : Base(,)",
        "open class Base(x: Int)\nclass C : Base(x = ,1)",
        "open class Base(x: Int)\nclass C : Base {\n    constructor() : super(,1)\n}",
    ])
    func frontendReportsEmptyArgumentElement(_ source: String) throws {
        let (_, context) = try buildASTModule(from: source, includeStdlib: false)
        #expect(context.diagnostics.diagnostics.contains {
            $0.code == "KSWIFTK-PARSE-0022" && $0.severity == .error
        })
    }

    @Test(arguments: [
        "open class Base(x: Int)\nclass C : Base(1 2)",
        "open class Base(x: Int)\nclass C : Base(x = 1 2)",
    ])
    func frontendReportsMissingSupertypeArgSeparator(_ source: String) throws {
        let (_, context) = try buildASTModule(from: source, includeStdlib: false)
        #expect(context.diagnostics.diagnostics.contains {
            $0.code == "KSWIFTK-PARSE-0015" && $0.severity == .error
        })
    }

    @Test
    func emptyArgumentElementDiagnosticPointsToComma() throws {
        let lexed = lex("f(,1)")
        let parser = BuildASTPhase.ExpressionParser(
            tokens: lexed.tokens.dropLast(),
            interner: lexed.interner,
            astArena: ASTArena(),
            diagnostics: lexed.diagnostics
        )
        _ = parser.parse()
        let diagnostic = try #require(lexed.diagnostics.diagnostics.first {
            $0.code == "KSWIFTK-PARSE-0022"
        })
        #expect(diagnostic.primaryRange?.start.offset == 2)
        #expect(diagnostic.primaryRange?.end.offset == 3)
    }

    @Test(arguments: [
        "f()", "f(1)", "f(1, 2)", "f(1,)", "f(1,\n2,\n)",
        "f(value = 1, other = 2)", "f(*items, 2)", "f(1 + 2)",
        "f(a to b)", "f(1L, 2u, 3UL, 4f)", "f(g(1, 2).size, 3)",
        "obj?.f<Int>(1, 2)", "f(1) { 2 }", "f({ 1 }, ({ 2 }))",
        "println(f(b = { 2 }(), a = { 3 }()))",
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

    @Test
    func frontendAcceptsNamedArgumentsWithImmediatelyInvokedLambdas() throws {
        let source = """
        fun f(a: Int, b: Int) = a * 10 + b
        fun main() {
            println(f(b = { 2 }(), a = { 3 }()))
        }
        """
        let (_, context) = try buildASTModule(from: source, includeStdlib: false)
        #expect(!context.diagnostics.diagnostics.contains {
            $0.code == "KSWIFTK-PARSE-0015"
        })
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

    @Test
    func rejectsFloatingLiteralFollowedByIdentifier() throws {
        let lexed = lex("1e5e5")
        let parser = BuildASTPhase.ExpressionParser(
            tokens: lexed.tokens.dropLast(),
            interner: lexed.interner,
            astArena: ASTArena(),
            diagnostics: lexed.diagnostics
        )

        #expect(parser.parse() != nil)
        let diagnostic = try #require(lexed.diagnostics.diagnostics.first {
            $0.code == "KSWIFTK-PARSE-0018"
        })
        #expect(diagnostic.severity == .error)
        #expect(diagnostic.message == "Unexpected token after expression.")
        #expect(diagnostic.primaryRange?.start.offset == 3)
    }

    @Test
    func frontendRejectsKuu1884MinimalReproduction() throws {
        let source = """
        fun main() {
            val f = 1e5e5
            println(f)
        }
        """
        let (_, context) = try buildASTModule(from: source, includeStdlib: false)

        let diagnostics = context.diagnostics.diagnostics.filter {
            $0.code == "KSWIFTK-PARSE-0018"
        }
        #expect(diagnostics.count == 1)
        let diagnostic = try #require(diagnostics.first)
        #expect(diagnostic.severity == .error)
        #expect(diagnostic.primaryRange?.start.offset == "fun main() {\n    val f = 1e5".utf8.count)
    }
}
#endif
