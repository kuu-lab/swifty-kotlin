#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct GenericCallContextConstraintTests {
    @Test
    func invariantFactoryUsesExpectedType() throws {
        let source = """
        sealed interface Slot { object Empty : Slot; class Task : Slot }
        class AtomicRef<T>(var value: T)
        fun <T> atomic(v: T): AtomicRef<T> = AtomicRef(v)
        class C {
            private val slot: AtomicRef<Slot> = atomic(Slot.Empty)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
            let sema = try #require(ctx.sema)
            let slot = try #require(sema.symbols.lookup(fqName: [ctx.interner.intern("Slot")]))
            let slotType = sema.types.make(.classType(ClassType(
                classSymbol: slot, args: [], nullability: .nonNull
            )))
            let call = try call(named: "atomic", path: path, in: ctx)
            let binding = try #require(sema.bindings.callBinding(for: call))
            #expect(binding.substitutedTypeArguments == [slotType])
        }
    }

    @Test(arguments: ["in ", "out ", ""])
    func lambdaBodyConstrainsContinuationType(variance: String) throws {
        let source = """
        interface CCont<\(variance)T>
        suspend fun <T> scc(block: (CCont<T>) -> Unit): T = null as T
        suspend fun f() {
            scc { continuation -> use(continuation) }
        }
        fun use(c: CCont<Unit>) {}
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
            let sema = try #require(ctx.sema)
            let call = try call(named: "scc", path: path, in: ctx)
            #expect(sema.bindings.exprType(for: call) == sema.types.unitType)
            let binding = try #require(sema.bindings.callBinding(for: call))
            #expect(binding.substitutedTypeArguments == [sema.types.unitType])
        }
    }

    @Test(arguments: [
        "val result: String = scc { use(it) }",
        "scc<String> { use(it) }",
    ])
    func incompatibleContinuationTypesAreRejected(statement: String) throws {
        let source = """
        interface CCont<in T>
        suspend fun <T> scc(block: (CCont<T>) -> Unit): T = null as T
        fun use(c: CCont<Unit>) {}
        suspend fun f() { \(statement) }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            #expect(ctx.diagnostics.hasError)
        }
    }

    @Test
    func allLambdaBodyUsesContributeConstraints() throws {
        let source = """
        interface CCont<in T>
        fun <T> scc(block: (CCont<T>) -> Unit): T = null as T
        fun useUnit(c: CCont<Unit>) {}
        fun useString(c: CCont<String>) {}
        fun f() {
            val result = scc { useUnit(it); useString(it) }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
            let sema = try #require(ctx.sema)
            let call = try call(named: "scc", path: path, in: ctx)
            #expect(sema.bindings.exprType(for: call) == sema.types.anyType)
        }
    }

    @Test
    func explicitLambdaParameterProvidesTypeEvidence() throws {
        let source = """
        interface CCont<in T>
        fun <T> scc(block: (CCont<T>) -> Unit): T = null as T
        fun f() { val result = scc { continuation: CCont<Unit> -> } }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
            let sema = try #require(ctx.sema)
            let call = try call(named: "scc", path: path, in: ctx)
            #expect(sema.bindings.exprType(for: call) == sema.types.unitType)
        }
    }

    @Test
    func incompatibleFactoryArgumentIsRejected() throws {
        let source = """
        interface Slot
        class AtomicRef<T>(var value: T)
        fun <T> atomic(v: T): AtomicRef<T> = AtomicRef(v)
        val slot: AtomicRef<Slot> = atomic("wrong")
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            #expect(ctx.diagnostics.hasError)
        }
    }

    @Test
    func suspendCoroutineRetainsItsIntrinsicLambdaBinding() throws {
        let source = """
        import kotlin.coroutines.*
        suspend fun f(): Int = suspendCoroutine { continuation -> }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], includeStdlib: false)
            try runSema(ctx)
            #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
            let sema = try #require(ctx.sema)
            let ast = try #require(ctx.ast)
            let call = try call(named: "suspendCoroutine", path: path, in: ctx)
            guard case let .call(_, _, arguments, _) = ast.arena.expr(call) else {
                Issue.record("Expected a suspendCoroutine call")
                return
            }
            #expect(sema.bindings.isCollectionHOFLambdaExpr(try #require(arguments.first).expr))
            #expect(sema.bindings.exprType(for: call) == sema.types.intType)
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
