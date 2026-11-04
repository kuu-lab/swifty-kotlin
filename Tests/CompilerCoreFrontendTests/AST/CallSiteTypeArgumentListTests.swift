#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerTestSupport
import Testing

/// KUU-4140: call-site explicit type arguments may end in a trailing comma —
/// `id<Int,>(x)` is accepted by kotlinc (Kotlin 1.4+ allows a trailing comma
/// in every comma-separated list). The declaration-side counterpart
/// (`fun <T,> f`) was KUU-3968; call sites parse through a different code
/// path (`tryParseExplicitTypeArgs` in BuildAST's expression parser), which
/// now mirrors the trailing-comma handling `TypeRefParserCore` already has
/// for nested type-argument lists.
@Suite
struct CallSiteTypeArgumentListTests {
    private func parseExpression(_ source: String) throws
        -> (expr: ExprID, arena: ASTArena, parser: BuildASTPhase.ExpressionParser,
            interner: StringInterner, diagnostics: DiagnosticEngine)
    {
        let lexed = lex(source)
        let arena = ASTArena()
        let parser = BuildASTPhase.ExpressionParser(
            tokens: lexed.tokens.dropLast(),
            interner: lexed.interner,
            astArena: arena,
            diagnostics: lexed.diagnostics
        )
        let expr = try #require(parser.parse())
        return (expr, arena, parser, lexed.interner, lexed.diagnostics)
    }

    @Test(arguments: [
        // Trailing comma, one or several arguments, before `(` or a lambda.
        ("id<Int,>(1)", 1),
        ("pair<Int, String,>(1, \"a\")", 2),
        ("Box<Int,>(2)", 1),
        // A `>` on its own line still closes the list.
        ("id<Int,\n>(1)", 1),
        ("id<\n    Int\n    ,\n>(1)", 1),
        // Nested lists keep their own trailing comma (`List<Int,>`).
        ("id<List<Int,>>(x)", 1),
        ("id<Map<String, List<Int,>,>,>(x)", 1),
    ])
    func trailingCommaCallParsesAsGenericCall(_ source: String, expectedTypeArgs: Int) throws {
        let (expr, arena, parser, _, diagnostics) = try parseExpression(source)

        guard case let .call(_, typeArgs, _, _) = arena.expr(expr) else {
            Issue.record("Expected an explicit generic call for \(source)")
            return
        }
        #expect(typeArgs.count == expectedTypeArgs)
        #expect(parser.current() == nil)
        #expect(!diagnostics.hasError, "Unexpected diagnostics: \(diagnostics.diagnostics)")
    }

    @Test
    func memberCallTrailingCommaParsesAsGenericCall() throws {
        let (expr, arena, parser, interner, diagnostics) = try parseExpression("box.get<Int,>(3)")

        guard case let .memberCall(_, callee, typeArgs, _, _) = arena.expr(expr) else {
            Issue.record("Expected a member call for box.get<Int,>(3)")
            return
        }
        #expect(callee == interner.intern("get"))
        #expect(typeArgs.count == 1)
        #expect(parser.current() == nil)
        #expect(!diagnostics.hasError, "Unexpected diagnostics: \(diagnostics.diagnostics)")
    }

    @Test
    func trailingCommaBeforeTrailingLambdaParsesAsGenericCall() throws {
        let (expr, arena, parser, _, diagnostics) = try parseExpression("run0<Int,> { 7 }")

        guard case let .call(_, typeArgs, args, _) = arena.expr(expr) else {
            Issue.record("Expected a call for run0<Int,> { 7 }")
            return
        }
        #expect(typeArgs.count == 1)
        #expect(args.count == 1)
        #expect(args.first?.isTrailingLambda == true)
        #expect(parser.current() == nil)
        #expect(!diagnostics.hasError, "Unexpected diagnostics: \(diagnostics.diagnostics)")
    }

    @Test
    func qualifiedCallTrailingCommaParsesThroughFrontend() throws {
        let (ast, ctx) = try buildASTModule(from: """
        fun <T> id(x: T): T = x
        fun <T, U> pair(a: T, b: U): T = a
        class Box<T>(val v: T) { fun <U> get(u: U): U = u }
        fun main() {
            println(id<Int,>(1))
            println(pair<Int, String,>(1, "a"))
            println(Box<Int,>(2).v)
            println(Box(0).get<Int,>(3))
        }
        """, includeStdlib: false)

        #expect(!ctx.diagnostics.hasError, "Unexpected diagnostics: \(ctx.diagnostics.diagnostics)")
        #expect(ast.arena.exprs.contains {
            if case let .call(_, typeArgs, _, _) = $0 { return typeArgs.count == 1 }
            return false
        })
        #expect(ast.arena.exprs.contains {
            if case let .memberCall(_, _, typeArgs, _, _) = $0 { return typeArgs.count == 1 }
            return false
        })
    }

    @Test(arguments: [
        // Empty list, opening comma, and doubled commas stay rejected —
        // kotlinc reports "syntax error: Type expected." for all of them.
        "id<>(1)",
        "id<,>(1)",
        "id<,Int>(1)",
        "id<Int,,>(1)",
        "id<Int,,String>(1)",
    ])
    func malformedTypeArgumentListsStayRejected(_ source: String) throws {
        let lexed = lex(source)
        let arena = ASTArena()
        let parser = BuildASTPhase.ExpressionParser(
            tokens: lexed.tokens.dropLast(),
            interner: lexed.interner,
            astArena: arena,
            diagnostics: lexed.diagnostics
        )
        _ = parser.parse()

        // The malformed `<…>` tokens must not be taken as type arguments:
        // the parse either reports a diagnostic or leaves the remainder
        // unconsumed for the enclosing context to reject.
        #expect(lexed.diagnostics.hasError || parser.current() != nil,
                "`\(source)` parsed cleanly — expected rejection")
        #expect(!arena.exprs.contains {
            if case let .call(_, typeArgs, _, _) = $0 { return !typeArgs.isEmpty }
            return false
        }, "`\(source)` must not produce a call carrying explicit type arguments")
        #expect(!arena.exprs.contains {
            if case let .memberCall(_, _, typeArgs, _, _) = $0 { return !typeArgs.isEmpty }
            return false
        }, "`\(source)` must not produce a member call carrying explicit type arguments")
    }

    @Test(arguments: [
        "id<>(1)",
        "id<,>(1)",
        "id<,Int>(1)",
        "id<Int,,>(1)",
        "id<Int,,String>(1)",
    ])
    func malformedTypeArgumentListsDiagnoseInFrontend(_ source: String) throws {
        let (_, ctx) = try buildASTModule(
            from: "fun <T> id(x: T): T = x\nfun main() { println(\(source)) }",
            includeStdlib: false
        )

        #expect(ctx.diagnostics.hasError,
                "Expected a diagnostic for `\(source)`, got none")
    }
}
#endif
