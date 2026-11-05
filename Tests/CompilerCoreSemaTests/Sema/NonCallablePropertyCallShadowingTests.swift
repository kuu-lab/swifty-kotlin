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

    /// KUU-3933: the same non-callable-member rule applies inside a secondary
    /// constructor's delegation call `this(...)`, where the class receiver is
    /// not yet available — the arguments still reach the file-scope function
    /// (the kotlinx-datetime `DatePeriod` shape: an `override val` member and
    /// a same-file `private fun` share the name `totalMonths`).
    @Test
    func memberPropertyDoesNotShadowTopLevelFunctionInDelegationCall() throws {
        let ctx = makeContextFromSource("""
        abstract class Base { internal abstract val totalMonths: Long }
        class D internal constructor(override val totalMonths: Long, val days: Int) : Base() {
            constructor(y: Int = 0, m: Int = 0, d: Int = 0) : this(totalMonths(y, m), d) {
                val check: Long = totalMonths
            }
        }
        private fun totalMonths(y: Int, m: Int): Long = y * 12L + m
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")

        let function = try topLevelFunction(named: "totalMonths", in: ctx)
        let calls = try bareCallIDs(named: "totalMonths", in: ctx)
        #expect(calls.count == 1)
        let sema = try #require(ctx.sema)
        #expect(sema.bindings.callBinding(for: try #require(calls.first))?.chosenCallee == function)

        // The call-position yield must not leak into value position: the bare
        // `totalMonths` read in the constructor body still binds the member
        // property, not the file-scope function. The arena spans the bundled
        // stdlib too, so match the member property symbol rather than a count.
        let ast = try #require(ctx.ast)
        let propertySymbol = try #require(sema.symbols.lookupAll(fqName: [
            ctx.interner.intern("D"), ctx.interner.intern("totalMonths"),
        ]).first {
            sema.symbols.symbol($0)?.kind == .property
        })
        var callCalleeIDs: Set<ExprID> = []
        var propertyReadIDs: [ExprID] = []
        for index in ast.arena.exprs.indices {
            let exprID = ExprID(rawValue: Int32(index))
            switch ast.arena.expr(exprID) {
            case let .call(callee, _, _, _):
                callCalleeIDs.insert(callee)
            case let .nameRef(name, _):
                if ctx.interner.resolve(name) == "totalMonths",
                   sema.bindings.identifierSymbol(for: exprID) == propertySymbol
                {
                    propertyReadIDs.append(exprID)
                }
            default:
                break
            }
        }
        #expect(!propertyReadIDs.isEmpty)
        #expect(propertyReadIDs.allSatisfy { !callCalleeIDs.contains($0) })
    }

    /// KUU-4062: `x.f()` can only target a callable member, so a `private`
    /// non-callable property is not a candidate — the call reports the
    /// unresolved-member diagnostic like kotlinc's "cannot be invoked",
    /// not a private-access error. The same gate applies to a private
    /// property inherited from a supertype.
    @Test(arguments: [
        "class A { private val f: Int = 1 }\nfun test(a: A) { a.f() }",
        "open class B { private val f: Int = 1 }\nclass D : B()\nfun test(d: D) { d.f() }",
    ])
    func privateNonCallableMemberPropertyDoesNotReportPrivateAccessOnCall(source: String) throws {
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        let codes = ctx.diagnostics.diagnostics.filter { $0.severity == .error }.map(\.code)
        #expect(codes.contains("KSWIFTK-SEMA-0024"), "\(ctx.diagnostics.diagnostics)")
        #expect(!codes.contains("KSWIFTK-SEMA-0040"), "\(ctx.diagnostics.diagnostics)")
    }

    /// The gate keeps reporting a genuinely callable `private` property:
    /// a function-typed member (plain or nullable) is a call candidate, so
    /// `x.f()` still reports the private-access error (KUU-4062).
    @Test(arguments: [
        "class A { private val f: () -> Int = { 1 } }\nfun test(a: A) { a.f() }",
        "class A { private val f: (() -> Int)? = null }\nfun test(a: A) { a.f() }",
    ])
    func privateCallableMemberPropertyStillReportsPrivateAccessOnCall(source: String) throws {
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        let codes = ctx.diagnostics.diagnostics.filter { $0.severity == .error }.map(\.code)
        #expect(codes.contains("KSWIFTK-SEMA-0040"), "\(ctx.diagnostics.diagnostics)")
    }
}
#endif
