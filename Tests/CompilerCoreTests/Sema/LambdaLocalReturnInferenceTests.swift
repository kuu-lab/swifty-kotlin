#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct LambdaLocalReturnInferenceTests {
    @Test func infersLocalReturnValuesAndFallthrough() throws {
        let source = """
        fun <T> evaluate(action: () -> T): T = action()
        fun main(flag: Boolean) {
            val implicit = evaluate { return@evaluate 13 }
            val explicit = evaluate<Int> { return@evaluate 13 }
            val text = evaluate text@{ return@text "value" }
            val branches = evaluate branches@{
                if (flag) return@branches 1
                return@branches 2
            }
            val fallthrough = evaluate fallthrough@{
                if (flag) return@fallthrough 1
                2
            }
            val nullable = evaluate nullable@{
                if (flag) return@nullable null
                3
            }
            val mixed = evaluate mixed@{
                if (flag) return@mixed "value"
                4
            }
            val unit = evaluate unit@{ return@unit }
            val terminated = evaluate terminated@{ return@terminated 5; }
            val standalone = standalone@{ return@standalone 6 }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")
            let sema = try #require(ctx.sema)
            try expectLambdaReturns([
                "evaluate": sema.types.intType,
                "text": sema.types.stringType,
                "branches": sema.types.intType,
                "fallthrough": sema.types.intType,
                "nullable": sema.types.makeNullable(sema.types.intType),
                "mixed": sema.types.anyType,
                "unit": sema.types.unitType,
                "terminated": sema.types.intType,
                "standalone": sema.types.intType,
            ], ctx: ctx, path: path)
        }
    }

    @Test func keepsNestedAndFunctionReturnTargetsSeparate() throws {
        let source = """
        fun <T> evaluate(action: () -> T): T = action()
        inline fun <T> inlineEvaluate(action: () -> T): T = action()
        fun enclosing(flag: Boolean): String {
            val nonlocal = inlineEvaluate nonlocal@{
                if (flag) return "function"
                1
            }
            val nested = evaluate outer@{
                evaluate inner@{ return@inner "inner" }
                return@outer 2
            }
            val targeted = inlineEvaluate targeted@{
                inlineEvaluate bridge@{ return@targeted 3 }
            }
            val local = evaluate local@{
                fun helper(): String { return "helper" }
                helper()
                return@local 4
            }
            val named = inlineEvaluate named@{
                if (flag) return@enclosing "named"
                return@named 5
            }
            val shadow = evaluate shadow@{
                evaluate shadow@{ return@shadow "shadow" }
                return@shadow 6
            }
            return "done"
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")
            let sema = try #require(ctx.sema)
            try expectLambdaReturns([
                "nonlocal": sema.types.intType,
                "outer": sema.types.intType,
                "inner": sema.types.stringType,
                "targeted": sema.types.intType,
                "bridge": sema.types.nothingType,
                "local": sema.types.intType,
                "named": sema.types.intType,
            ], ctx: ctx, path: path)
            let ast = try #require(ctx.ast)
            let shadowLambdas = allExprIDs(in: ast, path: path, ctx: ctx) { id, expr in
                guard sema.bindings.exprType(for: id) != nil else { return false }
                guard case let .lambdaLiteral(_, _, label?, _) = expr else { return false }
                return ctx.interner.resolve(label) == "shadow"
            }
            #expect(shadowLambdas.count == 2)
            let returnTypes = try shadowLambdas.map { id in
                let type = try #require(sema.bindings.exprType(for: id))
                guard case let .functionType(function) = sema.types.kind(of: type) else {
                    Issue.record("Expected a function type")
                    return sema.types.errorType
                }
                return function.returnType
            }
            #expect(Set(returnTypes) == Set([sema.types.intType, sema.types.stringType]))
        }
    }

    @Test func checksReturnAgainstItsTargetRatherThanNestedContext() throws {
        let ctx = makeContextFromSources([
            """
            inline fun consume(action: () -> Unit) { action() }
            inline fun <T> inlineEvaluate(action: () -> T): T = action()
            fun test(): Int = inlineEvaluate<Int> target@{
                consume { return@target 7 }
                8
            }
            """
        ])
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")
    }

    @Test(arguments: [
        "fun test() = evaluate<Int> { if (true) return@evaluate \"wrong\"; 1 }",
        "fun test() = evaluate<Int> { return@evaluate }",
        "fun test() = evaluate<Unit> { return@evaluate 1 }",
    ])
    func rejectsIncompatibleLocalReturn(source: String) throws {
        let ctx = makeContextFromSources([
            "fun <T> evaluate(action: () -> T): T = action()\n" + source
        ])
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError, "Expected an incompatible local return to be rejected")
    }

    private func expectLambdaReturns(
        _ expected: [String: TypeID],
        ctx: CompilationContext,
        path: String
    ) throws {
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        var seen: Set<String> = []
        let lambdas = allExprIDs(in: ast, path: path, ctx: ctx) { id, expr in
            guard sema.bindings.exprType(for: id) != nil else { return false }
            if case .lambdaLiteral = expr { return true }
            return false
        }
        for id in lambdas {
            guard case let .lambdaLiteral(_, _, label?, _) = ast.arena.expr(id),
                  let expectedType = expected[ctx.interner.resolve(label)] else { continue }
            let type = try #require(sema.bindings.exprType(for: id))
            guard case let .functionType(function) = sema.types.kind(of: type) else {
                Issue.record("Expected a function type")
                continue
            }
            #expect(function.returnType == expectedType, "Lambda \(ctx.interner.resolve(label))")
            seen.insert(ctx.interner.resolve(label))
        }
        #expect(seen == Set(expected.keys))
    }
}
#endif
