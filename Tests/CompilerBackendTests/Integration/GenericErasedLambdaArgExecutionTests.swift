import CompilerCore
import TestStdlibCache
import Testing

@Suite(.serialized)
struct GenericErasedLambdaArgExecutionTests {
    @Test(arguments: [true, false])
    func nullableStringThroughImportedInlineBody(allowDefaultStdlibLibrary: Bool) throws {
        TestStdlibCache.shared.prepare()
        let source = try diffCaseSource("kotlin_test_null.kt", file: #filePath)
        for optLevel in [OptimizationLevel.O0, .O2] {
            try compileAndRunKotlin(
                source,
                expectedOutput: "present\n7\nExpected value to be null, but was: <value>.\ncustom. Expected value to be not null.\n. Expected value to be null, but was: <1>.\n0\nlazy null message. Expected value to be null, but was: <value>.\n1\nblock\n1\ndeprecated failure. Expected value to be not null.\n1\n",
                moduleName: "NullableStringImportedInline",
                allowDefaultStdlibLibrary: allowDefaultStdlibLibrary,
                optLevel: optLevel
            )
        }
    }

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

    /// KUU-3345: an unchecked `Any as T` cast must retain the String handle
    /// representation when the value is passed to a generic function value.
    @Test(arguments: [true, false])
    func genericUncheckedCastThroughLambda(allowDefaultStdlibLibrary: Bool) throws {
        TestStdlibCache.shared.prepare()
        let source = try diffCaseSource("generic_lambda_bridge_cast.kt", file: #filePath)
        try compileAndRunKotlin(
            source,
            expectedOutput: "xOK\n",
            moduleName: "KUU3345GenericLambdaBridgeCast",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }

    /// KUU-3177: a receiver lambda invoked on an unchecked-cast generic value
    /// needs its erased invoke bridge to reject an incompatible receiver.
    @Test(arguments: [true, false])
    func genericExtensionLambdaAfterUncheckedCast(allowDefaultStdlibLibrary: Bool) throws {
        TestStdlibCache.shared.prepare()
        let source = try diffCaseSource("generic_extension_lambda_bridge_cast.kt", file: #filePath)
        try compileAndRunKotlin(
            source,
            expectedOutput: "OK\nClassCastException\n",
            moduleName: "KUU3177GenericExtensionLambdaBridgeCast",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }

    /// KUU-3506: non-explicitly-inline generic higher-order calls must preserve
    /// the erased String handle across identity, transforming, and referenced lambdas.
    @Test
    func genericHigherOrderFunctionValueCall() throws {
        TestStdlibCache.shared.prepare()
        try compileAndRunKotlin(
            """
            fun <T> idn(x: T): T = x
            fun <T, R> ap(s: R, a: (R) -> T) = a(s)
            fun <R> io(s: R, a: (R) -> R) = a(s)
            fun main() {
                println(ap("OK", { it }))
                println(ap("OK", { x -> x + "!" }))
                println(ap("OK", ::idn))
                println(io("SAME", { it }))
                println(io("REF", ::idn))
            }
            """,
            expectedOutput: "OK\nOK!\nOK\nSAME\nREF\n",
            moduleName: "KUU3506GenericHigherOrderFunctionValueCall"
        )
    }
}
