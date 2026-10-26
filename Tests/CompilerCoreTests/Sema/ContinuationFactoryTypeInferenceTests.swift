#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct ContinuationFactoryTypeInferenceTests {
    @Test
    func infersContinuationTypeFromResultAssignment() throws {
        let source = """
        import kotlin.coroutines.*
        val s: suspend () -> Int = { 5 }
        fun create() {
            var result: Result<Int>? = null
            s.startCoroutine(Continuation(EmptyCoroutineContext) { result = it })
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(errors.isEmpty, "\(errors)")
            let sema = try #require(ctx.sema)
            let call = try call(named: "Continuation", path: path, in: ctx)
            guard case let .classType(continuationType) = sema.types.kind(
                of: try #require(sema.bindings.exprType(for: call))
            ) else {
                Issue.record("Expected the Continuation factory to have a nominal type")
                return
            }
            #expect(continuationType.args == [.invariant(sema.types.intType)])
            #expect(sema.bindings.callBinding(for: call)?.substitutedTypeArguments == [sema.types.intType])
        }
    }

    private func call(named name: String, path: String, in ctx: CompilationContext) throws -> ExprID {
        let ast = try #require(ctx.ast)
        let calls = allExprIDs(in: ast, path: path, ctx: ctx) { _, expr in
            guard case let .call(callee, _, _, _) = expr,
                  case let .nameRef(calleeName, _) = ast.arena.expr(callee)
            else { return false }
            return ctx.interner.resolve(calleeName) == name
        }
        #expect(calls.count == 1)
        return try #require(calls.first)
    }
}
#endif
