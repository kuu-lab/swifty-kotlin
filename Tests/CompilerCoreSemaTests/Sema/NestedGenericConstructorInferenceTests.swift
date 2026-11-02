#if canImport(Testing)
@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct NestedGenericConstructorInferenceTests {
    @Test func nestedCtorInImplicitOuterArgumentPosition() throws {
        let ctx = makeContextFromSource("""
        class D<T : Any, R>(val t: T, val w: Int, val dv: R? = null)
        class W1<T : Any>(val d: D<T, T>, val o: Int)
        fun <T : Any> f(t: T) = W1(D(t, 1), 0)
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "\(errors)")
    }

    @Test func nestedCtorUnderExplicitOuterTypeArguments() throws {
        let ctx = makeContextFromSource("""
        class D<T : Any, R>(val t: T, val w: Int, val dv: R? = null)
        class W2<T : Any, R>(val d: D<T, R>)
        fun <T : Any, R> g(t: T): W2<T, Unit> = W2<T, Unit>(D(t, 1))
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "\(errors)")
    }

    @Test func nestedCtorInIfElseBranchUsesSiblingType() throws {
        let ctx = makeContextFromSource("""
        class OD<T : Any, R>(val t: T, val dv: R? = null)
        fun h(b: Boolean): OD<Boolean, Boolean> {
            val d = if (b) OD<Boolean, Boolean>(false) else OD(false)
            return d
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "\(errors)")
    }

    @Test func declaredReturnBoundaryCasesStillWork() throws {
        let ctx = makeContextFromSource("""
        class D<T : Any, R>(val t: T, val w: Int, val dv: R? = null)
        class W2<T : Any, R>(val d: D<T, R>)
        fun <T : Any> f1(t: T): D<T, Unit> = D(t, 1)
        fun <T : Any> f2(t: T): W2<T, Unit> = W2(D(t, 1))
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "\(errors)")
    }

    @Test(arguments: [
        "W2<T, Unit>(D(t, \"x\"))",
        "W2<T, Unit>(D(t))",
    ])
    func incompatibleNestedArgumentsStillFail(expression: String) throws {
        let ctx = makeContextFromSource("""
        class D<T : Any, R>(val t: T, val w: Int, val dv: R? = null)
        class W2<T : Any, R>(val d: D<T, R>)
        fun <T : Any> g(t: T): W2<T, Unit> = \(expression)
        """)
        try runSema(ctx)
        let hasError = ctx.diagnostics.hasError
        #expect(hasError, "Expected the invalid nested constructor call to fail")
    }

    @Test func nestedCtorInIfElseBlockUsesSiblingType() throws {
        let ctx = makeContextFromSource("""
        class OD<T : Any, R>(val t: T, val dv: R? = null)
        fun h(b: Boolean): OD<Boolean, Boolean> {
            val d = if (b) OD<Boolean, Boolean>(false) else {
                OD(false)
            }
            return d
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "\(errors)")
    }

    @Test func nestedCtorInWhenElseBlockUsesSiblingType() throws {
        let ctx = makeContextFromSource("""
        class TN<K, V>(val dataMap: Int, val nodeMap: Int, val buffer: Array<Any?>) {
            val ownedBy: Any? = null
            fun f(mutator: Any): TN<K, V> {
                var newDataMap = 0
                var newNodeMap = 0
                val mutableNode = when {
                    this.ownedBy == mutator -> this
                    else -> {
                        val newBuffer = arrayOfNulls<Any>(3)
                        TN(newDataMap, newNodeMap, newBuffer)
                    }
                }
                return mutableNode
            }
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "\(errors)")
    }

    @Test func nestedCtorInWhenSubjectBranchUsesSiblingType() throws {
        let ctx = makeContextFromSource("""
        class TN<K, V>(val dataMap: Int, val nodeMap: Int, val buffer: Array<Any?>) {
            val ownedBy: Any? = null
            fun f(mutator: Any): TN<K, V> {
                var newDataMap = 0
                var newNodeMap = 0
                val mutableNode = when (ownedBy) {
                    mutator -> this
                    else -> TN(newDataMap, newNodeMap, arrayOfNulls<Any>(3))
                }
                return mutableNode
            }
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        #expect(errors.isEmpty, "\(errors)")
    }

    @Test func incompatibleWhenSiblingStillFails() throws {
        let ctx = makeContextFromSource("""
        class OD<T : Any, R>(val t: T, val dv: R? = null)
        fun odBool(): OD<Boolean, Boolean> = OD(false)
        fun h(b: Boolean) {
            val d = when {
                b -> odBool()
                else -> OD("x")
            }
        }
        """)
        try runSema(ctx)
        let hasError = ctx.diagnostics.hasError
        #expect(hasError, "Expected a when whose branches disagree to fail")
    }

    @Test func incompatibleIfElseSiblingStillFails() throws {
        let ctx = makeContextFromSource("""
        class OD<T : Any, R>(val t: T, val dv: R? = null)
        fun h(b: Boolean) {
            val d = if (b) OD<Boolean, Boolean>(false) else OD("x")
        }
        """)
        try runSema(ctx)
        let hasError = ctx.diagnostics.hasError
        #expect(hasError, "Expected an if/else whose branches disagree to fail")
    }

    @Test func standaloneNestedCtorWithoutExpectedTypeStillReportsInfer() throws {
        let ctx = makeContextFromSource("""
        class D<T : Any, R>(val t: T, val w: Int, val dv: R? = null)
        fun <T : Any> f(t: T) { val x = D(t, 1) }
        """)
        try runSema(ctx)
        let codes = ctx.diagnostics.diagnostics.map(\.code)
        #expect(codes.contains("KSWIFTK-SEMA-INFER"))
    }

    /// KUU-4018 regression for the foreign-typeParam guard in `inferCallExpr`:
    /// the inner `arrayOf` receives the *outer* call's unresolved element
    /// variable as its expected type, and both calls share the `arrayOf`
    /// callee so the variable's symbol matches the inner callee's own type
    /// parameter. The KUU-3937 self-pin must not bind it as lexical — a
    /// leaked `T` degraded `arrayOf(1)` to `Array<Any>`, breaking
    /// `Array<Array<Int>>::class.isInstance(arrayOf(arrayOf(1)))`.
    @Test func nestedSameCalleeCallKeepsElementInference() throws {
        let ctx = makeContextFromSource("""
        fun main() {
            val x = arrayOf(arrayOf(1))
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let inner = try innerCall(named: "arrayOf", in: ctx)
        let binding = try #require(sema.bindings.callBinding(for: inner))
        #expect(
            binding.substitutedTypeArguments == [sema.types.intType],
            "inner arrayOf(1) must infer Int, got \(binding.substitutedTypeArguments)"
        )
    }

    /// Same foreign-typeParam leak through the member-call entry point
    /// (`dropForeignTypeParamExpectedType` in `inferMemberCall`): the inner
    /// `b.wrap(1)` must not bind the outer `wrap`'s inference variable `E`
    /// just because both calls resolve to the same callee.
    @Test func nestedSameCalleeMemberCallKeepsElementInference() throws {
        let ctx = makeContextFromSource("""
        class Box {
            fun <E> wrap(v: E): E = v
        }
        fun main() {
            val b = Box()
            val y = b.wrap(b.wrap(1))
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
        let sema = try #require(ctx.sema)
        let inner = try innerCall(named: "wrap", in: ctx)
        let binding = try #require(sema.bindings.callBinding(for: inner))
        #expect(
            binding.substitutedTypeArguments == [sema.types.intType],
            "inner b.wrap(1) must infer Int, got \(binding.substitutedTypeArguments)"
        )
    }

    /// The inner call of `f(f(1))`-shaped nests: the user-source call to
    /// `name` whose first argument is not itself a call.
    private func innerCall(named name: String, in ctx: CompilationContext) throws -> ExprID {
        let ast = try #require(ctx.ast)
        let interned = ctx.interner.intern(name)
        let calls = ast.arena.exprs.indices.compactMap { index -> ExprID? in
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID),
                  isUserSourceExpr(exprID, in: ctx)
            else { return nil }
            switch expr {
            case let .call(callee, _, _, _):
                guard case let .nameRef(calleeName, _) = ast.arena.expr(callee),
                      calleeName == interned
                else { return nil }
            case let .memberCall(_, callee, _, _, _):
                guard callee == interned else { return nil }
            default:
                return nil
            }
            return exprID
        }
        return try #require(calls.first { exprID in
            let expr = ast.arena.expr(exprID)
            let firstArg: ExprID?
            switch expr {
            case let .call(_, _, arguments, _):
                firstArg = arguments.first?.expr
            case let .memberCall(_, _, _, arguments, _):
                firstArg = arguments.first?.expr
            default:
                firstArg = nil
            }
            guard let firstArg, let argExpr = ast.arena.expr(firstArg) else { return false }
            if case .call = argExpr { return false }
            if case .memberCall = argExpr { return false }
            return true
        }, "expected a nested \(name) call whose argument is not a call")
    }
}
#endif
