@testable import CompilerCore
import Testing
@testable import CompilerTestSupport

@Suite
struct CallableIntersectionInvocationTests {
    @Test
    func functionInterfaceImplementationsRemainCallableThroughFunctionTypes() throws {
        let ctx = makeContextFromSource("""
        fun interface KRunnable {
            fun invoke()
        }

        fun interface KBoolean {
            fun invoke(b: Boolean)
        }

        fun useFunInterface(fn: KRunnable) { fn.invoke() }
        fun useFunInterfacePredicate(fn: KBoolean) { fn.invoke(true) }

        fun <T> testIntersection(x: T) where T : () -> Unit, T : (Boolean) -> Unit {
            useFunInterface(x)
            useFunInterfacePredicate(x)
        }

        var result = ""

        object Test : () -> Unit, (Boolean) -> Unit {
            override fun invoke() { result += "O" }
            override fun invoke(p1: Boolean) { if (p1) result += "K" }
        }

        fun interface KRunnableSubtype {
            fun invoke()
        }

        object OK : () -> Unit {
            override fun invoke() { result = "OK" }
        }

        fun useSubtype(fn: KRunnableSubtype) { fn.invoke() }

        fun exercise() {
            testIntersection(Test)
            useSubtype(OK)
        }
        """)
        try runSema(ctx)

        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    @Test
    func functionTypeRemainsCallableAfterKFunctionCast() throws {
        let ctx = makeContextFromSource("""
        fun render(value: Boolean): String = value.toString()
        fun applyOp(op: (Int) -> Int): Int = op(1)
        fun main() {
            val reference: (Boolean) -> Any = ::render
            val reflected = reference as kotlin.reflect.KFunction<*>
            val result = reference(true)
            val name = reflected.name

            val higherOrder: ((Int) -> Int) -> Int = ::applyOp
            val higherReflected = higherOrder as kotlin.reflect.KFunction<*>
            val number = higherOrder { it + 1 }
            val higherName = higherReflected.name
        }
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    // KUU-4457: a `where`-bounded type variable passes through its function
    // bound. `F : (T) -> R, F : KCallable<R>` must satisfy a `(T) -> R`
    // parameter, binding T and R through the bound's components.
    @Test
    func multiBoundTypeParameterSatisfiesFunctionBound() throws {
        let ctx = makeContextFromSource("""
        import kotlin.reflect.KCallable

        class Assert<T>(val v: T)
        fun <T, R> Assert<T>.having(name: String?, callable: (T) -> R): Assert<R> = Assert(callable(v))

        fun <T, R, F> Assert<T>.having(callable: F): Assert<R> where F : (T) -> R, F : KCallable<R> =
            having(callable.name, callable)

        fun checked(): Assert<Int> = Assert(1).having(Int::inc)
        """)
        try runSema(ctx)
        #expect(!ctx.diagnostics.hasError, "\(ctx.diagnostics.diagnostics)")
    }

    // The bound's components keep full contravariance/covariance: a bound
    // `(T) -> R` cannot satisfy a differently shaped `(T, T) -> R` parameter.
    @Test
    func multiBoundTypeParameterRejectsMismatchedFunctionShape() throws {
        let ctx = makeContextFromSource("""
        import kotlin.reflect.KCallable

        fun <T, R> takesPair(callable: (T, T) -> R) = Unit
        fun <T, R, F> use(callable: F) where F : (T) -> R, F : KCallable<R> =
            takesPair(callable)
        """)
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError, "(T) -> R bound must not satisfy (T, T) -> R")
    }

    @Test(arguments: [
        """
        fun render(value: Boolean): String = value.toString()
        fun test() {
            val reference: (Boolean) -> String = ::render
            val reflected = reference as kotlin.reflect.KFunction<*>
            reference(1)
        }
        """,
        """
        fun test(value: Any) {
            val reflected = value as kotlin.reflect.KFunction<*>
            value(1)
        }
        """,
    ])
    func rejectsInvalidInvocationAfterCast(source: String) throws {
        let ctx = makeContextFromSource(source)
        try runSema(ctx)
        #expect(ctx.diagnostics.hasError, "Expected rejection: \(source)")
    }
}
