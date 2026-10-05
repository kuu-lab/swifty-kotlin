#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct GenericSuspendNullableReturnInferenceTests {
    @Test
    func nestedNullableCoroutineResultsRetainTheirInferredType() throws {
        let source = """
        import kotlinx.coroutines.*

        suspend fun <T> wrap(block: suspend () -> T): T? =
            withTimeoutOrNull(50L) { block() }

        fun blockingProbe() {
            val blocking = runBlocking { withTimeoutOrNull(50L) { "x" } }
        }

        suspend fun probe() {
            val timed = withTimeout(5000) { withTimeoutOrNull(50L) { "x" } }
            val nullableTimed = withTimeoutOrNull(5000) { withTimeoutOrNull(50L) { "x" } }
            val scoped = coroutineScope { withTimeoutOrNull(50L) { "x" } }
            val supervised = supervisorScope { withTimeoutOrNull(50L) { "x" } }
            val switched = withContext(Dispatchers.Default) { withTimeoutOrNull(50L) { "x" } }
            val explicit: String? = withTimeout(5000) { withTimeoutOrNull(50L) { "x" } }
            val nullOnly = withTimeout(5000) { withTimeoutOrNull(50L) { null } }
            val nullableBody = withTimeout(5000) { withTimeoutOrNull(50L) { null as String? } }
            val wrapped = wrap { "x" }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
            let sema = try #require(ctx.sema)
            let ast = try #require(ctx.ast)
            let names = Set(["blocking", "timed", "nullableTimed", "scoped", "supervised", "switched", "explicit", "nullableBody", "wrapped"])
            var checked = Set<String>()
            for index in ast.arena.exprs.indices {
                let expr = ExprID(rawValue: Int32(index))
                guard case let .localDecl(name, _, _, initializer, _, _) = ast.arena.expr(expr),
                      let initializer else { continue }
                let text = ctx.interner.resolve(name)
                if names.contains(text) {
                    #expect(sema.bindings.exprType(for: initializer) == sema.types.makeNullable(sema.types.stringType))
                    checked.insert(text)
                } else if text == "nullOnly" {
                    #expect(sema.bindings.exprType(for: initializer) == sema.types.nullableNothingType)
                    checked.insert(text)
                }
            }
            #expect(checked == names.union(["nullOnly"]))
        }
    }

    @Test(arguments: [
        "val result: String = withTimeout(5000) { withTimeoutOrNull(50L) { \"x\" } }",
        "val result: Int? = withTimeout(5000) { withTimeoutOrNull(50L) { \"x\" } }",
        "val result: String = withTimeoutOrNull(50L) { \"x\" }",
        "val result = withTimeout<String>(5000L) { null }",
    ])
    func incompatibleExpectedTypesAreStillRejected(statement: String) throws {
        let source = """
        import kotlinx.coroutines.*
        suspend fun probe() {
            \(statement)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            #expect(ctx.diagnostics.hasError, "Expected rejection of \(statement)")
        }
    }
}
#endif
