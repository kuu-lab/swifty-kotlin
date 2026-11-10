#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct SuspendFunctionReceiverBuilderAliasTests {
    /// KUU-4212: the upstream `remoteCallFlow` builder has a suspend
    /// Function0 receiver and imports `unsafeFlow as flow` beside a same-name
    /// package builder. Its extra implicit receiver must not make the two
    /// function-shaped candidates ambiguous.
    @Test
    func suspendFunctionReceiverBuilderCallPrefersExplicitAlias() throws {
        let sources = [
            """
            package imported
            class Flow<T>
            interface FlowCollector<T> {
                suspend fun emit(value: T)
            }
            fun <T> unsafeFlow(block: suspend FlowCollector<T>.() -> Unit): Flow<T> = Flow()
            """,
            """
            package repro
            import imported.Flow
            import imported.FlowCollector
            import imported.unsafeFlow as flow

            fun <T> flow(block: suspend FlowCollector<T>.() -> Unit): Flow<T> = Flow()

            fun <T> (() -> T).asFlow(): Flow<T> = flow { emit(invoke()) }
            fun <T> (suspend () -> T).asFlow(): Flow<T> = flow { emit(invoke()) }

            suspend fun remoteCall(): Int = 42
            fun remoteCallFlow(): Flow<Int> = ::remoteCall.asFlow()
            """,
        ]
        try withTemporaryFiles(contents: sources) { paths in
            let ctx = makeCompilationContext(inputs: paths, includeStdlib: false)
            try runSema(ctx)
            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(errors.isEmpty, "Unexpected diagnostics: \(errors.map { "\($0.code): \($0.message)" })")

            let sema = try #require(ctx.sema)
            let aliasedBuilder = try #require(sema.symbols.lookup(fqName: [
                ctx.interner.intern("imported"), ctx.interner.intern("unsafeFlow"),
            ]))
            let ast = try #require(ctx.ast)
            let sourceFile = try #require(ctx.sourceManager.fileID(forPath: paths[1]))
            let selectedBuilders = sema.bindings.callBindings.compactMap { expression, binding -> SymbolID? in
                guard case let .call(callee, _, _, _) = ast.arena.expr(expression),
                      case let .nameRef(name, _) = ast.arena.expr(callee),
                      ctx.interner.resolve(name) == "flow",
                      ast.arena.exprRange(expression)?.start.file == sourceFile
                else { return nil }
                return binding.chosenCallee
            }
            #expect(selectedBuilders.count == 2, "Expected both asFlow overloads to call the builder")
            #expect(selectedBuilders.allSatisfy { $0 == aliasedBuilder }, "Expected the explicit flow alias, got: \(selectedBuilders)")
        }
    }
}
#endif
