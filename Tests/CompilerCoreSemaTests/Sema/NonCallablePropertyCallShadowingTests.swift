#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

/// KUU-3913: a same-named property that cannot be invoked never occupies the
/// callable namespace, so `name()` keeps resolving callables in outer scopes
/// — the shape behind ktor-http's `allStatusCodes`.
@Suite
struct NonCallablePropertyCallShadowingTests {
    private func bareCallIDs(named name: String, in ctx: CompilationContext) throws -> [ExprID] {
        let ast = try #require(ctx.ast)
        return ast.arena.exprs.indices.compactMap { index in
            let exprID = ExprID(rawValue: Int32(index))
            guard case let .call(callee, _, _, _) = ast.arena.expr(exprID),
                  case let .nameRef(calleeName, _) = ast.arena.expr(callee),
                  ctx.interner.resolve(calleeName) == name
            else {
                return nil
            }
            return exprID
        }
    }

    private func topLevelFunction(named name: String, in ctx: CompilationContext) throws -> SymbolID {
        let sema = try #require(ctx.sema)
        return try #require(sema.symbols.lookupAll(fqName: [ctx.interner.intern(name)]).first { candidate in
            sema.symbols.symbol(candidate)?.kind == .function
        })
    }

    @Test
    func companionMemberPropertyDoesNotShadowTopLevelFunctionCall() throws {
        // The ticket's reproducer: inside the companion initializer the
        // member `val` binds `allStatusCodes` for value reads, but
        // `allStatusCodes()` must still reach the top-level function.
        let ctx = makeContextFromSource("""
        class StatusCode {
            companion object {
                public val allStatusCodes: List<StatusCode> = allStatusCodes()
            }
        }
        internal fun allStatusCodes(): List<StatusCode> = listOf(StatusCode())
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")

        let function = try topLevelFunction(named: "allStatusCodes", in: ctx)
        let calls = try bareCallIDs(named: "allStatusCodes", in: ctx)
        #expect(calls.count == 1)
        let sema = try #require(ctx.sema)
        #expect(sema.bindings.callBinding(for: try #require(calls.first))?.chosenCallee == function)
    }

    @Test
    func classMemberPropertyDoesNotShadowTopLevelFunctionCall() throws {
        let ctx = makeContextFromSource("""
        class StatusCode {
            val allStatusCodes: List<StatusCode> = allStatusCodes()
        }
        internal fun allStatusCodes(): List<StatusCode> = listOf(StatusCode())
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")

        let function = try topLevelFunction(named: "allStatusCodes", in: ctx)
        let calls = try bareCallIDs(named: "allStatusCodes", in: ctx)
        #expect(calls.count == 1)
        let sema = try #require(ctx.sema)
        #expect(sema.bindings.callBinding(for: try #require(calls.first))?.chosenCallee == function)
    }

    @Test
    func memberPropertyDoesNotShadowTopLevelFunctionInsideMethod() throws {
        // The same rule applies from a member body, not only an initializer.
        let ctx = makeContextFromSource("""
        class StatusCode {
            companion object {
                val allStatusCodes: List<StatusCode> = listOf()
                fun probe(): List<StatusCode> = allStatusCodes()
            }
        }
        internal fun allStatusCodes(): List<StatusCode> = listOf(StatusCode())
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")

        let function = try topLevelFunction(named: "allStatusCodes", in: ctx)
        let calls = try bareCallIDs(named: "allStatusCodes", in: ctx)
        #expect(calls.count == 1)
        let sema = try #require(ctx.sema)
        #expect(sema.bindings.callBinding(for: try #require(calls.first))?.chosenCallee == function)
    }

    @Test
    func callableMemberPropertyStillShadowsOuterFunction() throws {
        // A function-typed member `val` IS a call candidate, so the nearer
        // property keeps winning over the outer-tier function.
        let ctx = makeContextFromSource("""
        fun f(): Int = 100
        class A {
            val f: () -> Int = { 42 }
            fun test() = f()
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")

        let function = try topLevelFunction(named: "f", in: ctx)
        let calls = try bareCallIDs(named: "f", in: ctx)
        #expect(calls.count == 1)
        let sema = try #require(ctx.sema)
        let call = try #require(calls.first)
        #expect(sema.bindings.callBinding(for: call)?.chosenCallee != function)
    }
}
#endif
