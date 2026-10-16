#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct UnitCoercionGenericCallInferenceTests {
    @Test
    func unitUpperBoundOutputVariableCoercesLambdaBody() throws {
        let source = """
        fun <U : Unit> fork(task: () -> U) {}
        fun <T> infer(task: () -> T) {}
        fun test() {
            fork { 42 }
            infer { 42 }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")

            let sema = try #require(ctx.sema)
            let forkCall = try call(named: "fork", path: path, in: ctx)
            let inferCall = try call(named: "infer", path: path, in: ctx)
            #expect(sema.bindings.callBinding(for: forkCall)?.substitutedTypeArguments == [sema.types.unitType])
            #expect(sema.bindings.callBinding(for: inferCall)?.substitutedTypeArguments == [sema.types.intType])
        }
    }

    @Test
    func discardedGenericCallUsesItsEffectiveUpperBound() throws {
        let source = """
        fun <K> materialize(): K = "str" as K
        fun consume(block: () -> Unit) {}
        fun run() {
            consume { materialize() }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")

            let sema = try #require(ctx.sema)
            let callExpr = try call(named: "materialize", path: path, in: ctx)
            let binding = try #require(sema.bindings.callBinding(for: callExpr))
            #expect(binding.substitutedTypeArguments == [sema.types.nullableAnyType])
        }
    }

    @Test
    func explicitAndFixedReturnCallsRemainAccepted() throws {
        let source = """
        fun <K> materialize(): K = "str" as K
        fun fixed(): String = "str"
        fun consume(block: () -> Unit) {}
        fun run() {
            consume { materialize<String>() }
            consume { fixed() }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")
        }
    }

    @Test
    func genericCallWithConsumedValueStillRequiresInferenceEvidence() throws {
        let source = """
        fun <K> materialize(): K = "str" as K
        fun consume(block: () -> Unit) {}
        fun run() {
            consume {
                val value = materialize()
            }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            #expect(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-INFER" },
                    "Expected an inference diagnostic, got: \(ctx.diagnostics.diagnostics)")
        }
    }

    @Test
    func discardedScopeCallCoercesItsGenericLambdaResultToUnit() throws {
        let source = """
        fun <T, R> T.let(block: (T) -> R): R = block(this)
        fun <T> myRun(action: () -> T): T = action()
        fun foo(): String = "foo"
        var result = "fail"
        fun <K> materialize(): K {
            result = "K"
            return "str" as K
        }
        fun test1(n: Int, b: Boolean) {
            n.let {
                if (b) return@let
                myRun {
                    result = "O"
                    foo()
                }
            }
        }
        fun test2(n: Int, b: Boolean) {
            n.let {
                if (b) return@let
                materialize()
            }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "Got: \(ctx.diagnostics.diagnostics)")
        }
    }

    private func call(named name: String, path: String, in ctx: CompilationContext) throws -> ExprID {
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let calls = allExprIDs(in: ast, path: path, ctx: ctx) { id, expr in
            guard case let .call(callee, _, _, _) = expr,
                  case let .nameRef(calleeName, _) = ast.arena.expr(callee)
            else { return false }
            return ctx.interner.resolve(calleeName) == name
                && sema.bindings.callBinding(for: id) != nil
        }
        #expect(calls.count == 1)
        return try #require(calls.first)
    }
}
#endif
