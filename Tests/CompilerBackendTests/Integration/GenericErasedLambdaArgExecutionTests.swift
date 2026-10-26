import TestStdlibCache
import Testing

@Suite(.serialized)
struct GenericErasedLambdaArgExecutionTests {
    /// KUU-3438: a nullable-underlying value class returned through a generic
    /// function-value call must be unboxed before reaching a concrete use site.
    @Test(arguments: [true, false])
    func nullableAnyValueClassReturnedFromGenericLambda(allowDefaultStdlibLibrary: Bool) throws {
        TestStdlibCache.shared.prepare()
        try compileAndRunKotlin(
            """
            @JvmInline
            value class X(val x: Any?)
            fun useX(x: X): String = x.x as String
            fun <T> call(fn: () -> T) = fn()
            fun main() { println(useX(call { X("OK") })) }
            """,
            expectedOutput: "OK\n",
            moduleName: "KUU3438NullableAnyValueClassGenericLambda",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }

    /// KUU-3195 (JetBrains `finally/kt4134.kt`): a String argument substituted
    /// into an erased parameter slot of an inlined generic body kept its flat
    /// aggregate representation, so erased consumers (`kk_function_invoke`
    /// adapters, `kk_any_to_string`) read the aggregate fields as argument
    /// registers and crashed. The expanded binding must box the argument into
    /// its raw `kk_string_from_flat` handle first.
    @Test(arguments: [true, false])
    func finallyNestedTryGenericLambdaArg(allowDefaultStdlibLibrary: Bool) throws {
        TestStdlibCache.shared.prepare()
        try compileAndRunKotlin(
            """
            fun <T, R> io(s: R, a: (R) -> T): T {
                try { return a(s) }
                finally { try { s.toString() } catch(e: Exception) {} }
            }
            fun main() { println(io("OK") { it }) }
            """,
            expectedOutput: "OK\n",
            moduleName: "KUU3195FinallyGenericLambdaArg",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }

    /// The same erased-slot substitution without any try/finally: `a(s)` on a
    /// `String` argument dispatched through the function-value adapter.
    @Test(arguments: [true, false])
    func genericIdentityLambdaOnStringArg(allowDefaultStdlibLibrary: Bool) throws {
        TestStdlibCache.shared.prepare()
        try compileAndRunKotlin(
            """
            fun <R> io(s: R, a: (R) -> R): R {
                return a(s)
            }
            fun <T, R> io2(s: R, a: (R) -> T): T {
                return a(s)
            }
            fun main() {
                println(io("OK") { it })
                val x = "var-OK"
                println(io(x) { it })
                println(io(5) { it })
                println(io2("OK2") { it })
            }
            """,
            expectedOutput: "OK\nvar-OK\n5\nOK2\n",
            moduleName: "KUU3195GenericIdentityLambdaArg",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }
}
