@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

/// `c(t)` on `c: F` where `F : (T) -> R` invokes the call through the type
/// parameter's unique function-typed upper bound, the same way a smart-cast
/// intersection invokes its structural conjunct (KUU-4087).
@Suite
struct TypeParameterFunctionBoundInvocationTests {
    @Test
    func whereClauseFunctionBoundIsInvocable() throws {
        let ctx = makeContextFromSource("""
        fun <T, R, F> useFn(t: T, c: F): R where F : (T) -> R = c(t)
        fun inc(x: Int) = x + 1
        fun main() { println(useFn(2, ::inc)) }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test
    func inlineFunctionBoundIsInvocable() throws {
        let ctx = makeContextFromSource("""
        fun <T, R, F : (T) -> R> applyBound(t: T, c: F): R = c(t)
        fun inc(x: Int) = x + 1
        fun main() { println(applyBound(2, ::inc)) }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test
    func combinedBoundInvokesThroughFunctionBound() throws {
        // assertk `having`/`prop` shape: the function-type bound keeps `c(t)`
        // resolvable even when `F` also carries a `KCallable<R>` bound.
        let ctx = makeContextFromSource("""
        import kotlin.reflect.KCallable
        fun <T, R, F> having(t: T, callable: F): R where F : (T) -> R, F : KCallable<R> = callable(t)
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test
    func chainedTypeParameterBoundIsInvocable() throws {
        let ctx = makeContextFromSource("""
        fun <T, R, G : (T) -> R, F : G> chained(t: T, c: F): R = c(t)
        fun inc(x: Int) = x + 1
        fun main() { println(chained(2, ::inc)) }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test
    func explicitInvokeThroughFunctionBound() throws {
        let ctx = makeContextFromSource("""
        fun <T, R, F : (T) -> R> explicit(t: T, c: F): R = c.invoke(t)
        fun <T, R, F : ((T) -> R)?> safeCall(t: T, c: F): R? = c?.invoke(t)
        fun inc(x: Int) = x + 1
        fun main() {
            println(explicit(2, ::inc))
            println(safeCall(3, ::inc))
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test
    func memberPropertyWithFunctionBoundIsInvocable() throws {
        let ctx = makeContextFromSource("""
        class Box<T, F : (T) -> T>(val t: T, val c: F) {
            fun go(): T = c(t)
            fun goExplicit(): T = c.invoke(t)
        }
        fun inc(x: Int) = x + 1
        fun main() {
            println(Box(9, ::inc).go())
            println(Box(9, ::inc).goExplicit())
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test
    func callableValueShadowsFunctionForTrailingLambda() throws {
        // The bound-bound local also shadows a same-named function for a
        // trailing-lambda call: `it` must bind through the bound's parameter
        // type, not the shadowed `c(String)` signature.
        let ctx = makeContextFromSource("""
        fun c(x: String) = "top-level $x"
        fun <F : ((Int) -> Int) -> Int> higherOrder(c: F): Int = c { it + 1 }
        fun twice(f: (Int) -> Int): Int = f(10) + f(20)
        fun main() { println(higherOrder(::twice)) }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test
    func callableValueShadowsInapplicableFunctionCandidate() throws {
        // The in-scope top-level `c(String)` fails for `c(t: T)`, but the
        // value parameter `c: F` is callable through its bound and must win
        // instead of surfacing the failed candidate's diagnostic.
        let ctx = makeContextFromSource("""
        fun c(x: String) = "top-level $x"
        fun <T, R, F : (T) -> R> callIt(t: T, c: F): R = c(t)
        fun inc(x: Int) = x + 1
        fun main() { println(callIt(2, ::inc)) }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test(arguments: [
        """
        fun <T, R, F> bad(t: T, c: F, s: String): R where F : (T) -> R = c(s)
        """,
        """
        fun <T, R, F : (T) -> R> badArity(t: T, c: F): R = c()
        """,
        """
        fun <T, R, F> noBound(t: T, c: F): R = c(t)
        """,
    ])
    func rejectsInvalidInvocationThroughBound(source: String) throws {
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError, "Expected rejection: \(source)")
    }
}
