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

    @Test
    func inferredGenericUncheckedCastResultThroughNullAssertion() throws {
        TestStdlibCache.shared.prepare()
        try compileAndRunKotlin(
            """
            @Suppress("UNCHECKED_CAST")
            fun <T> f() = 1L as T
            fun main() {
                val x: Int = f()!!
                println(x)
            }
            """,
            expectedOutput: "1\n",
            moduleName: "KUU3538GenericUncheckedCastNullAssertion"
        )
    }

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

    @Test
    func genericExtensionOnStringCompanionWithLambdaArgument() throws {
        TestStdlibCache.shared.prepare()
        try compileAndRunKotlin(
            try diffCaseSource("generic_extension_companion_lambda.kt", file: #filePath),
            expectedOutput: "true\n",
            moduleName: "KUU3675GenericExtensionCompanionLambda"
        )
    }

    @Test(arguments: [true, false])
    func genericFoldLambdaPrimitiveCheckcastUnbox(allowDefaultStdlibLibrary: Bool) throws {
        TestStdlibCache.shared.prepare()
        try compileAndRunKotlin(
            """
            fun <A> fold(seed: A, step: (Int, A) -> A): A = step(1, seed)
            fun <A> foldLongFirst(seed: A, step: (Long, A) -> A): A = step(1L, seed)
            fun <A> foldMiddle(seed: A, step: (A, Int, A) -> A): A = step(seed, 2, seed)
            fun main() {
                println(fold(0) { element: Int, accumulator: Long -> accumulator + element })
                println(fold(0L) { element: Int, accumulator: Long -> accumulator + element })
                println(fold<Long>(0) { element: Int, accumulator: Long -> accumulator + element })
                println(fold(0) { element: Int, accumulator: Int -> accumulator + element })
                println(foldLongFirst(0L) { element: Long, accumulator: Long -> accumulator + element })
                println(foldMiddle(0L) { a: Long, e: Int, b: Long -> a + e + b })
            }
            """,
            expectedOutput: "1\n1\n1\n1\n1\n2\n",
            moduleName: "KUU3689GenericFoldLambdaPrimitiveCheckcastUnbox",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }
}
