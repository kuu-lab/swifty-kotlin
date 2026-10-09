#if canImport(Testing)
@testable import CompilerCore
import Testing

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
}
#endif
