import Testing
import TestStdlibCache

@Suite(.serialized)
struct CallableReferenceAdaptationExecutionTests {
    @Test func boundReferencePassedToCrossinlineInvokesInsideAnonymousObject() throws {
        try compileAndRunKotlin(
            """
            inline fun inlineFun(crossinline lambda: () -> String) =
                object { fun foo() = lambda.invoke() }.foo()
            class A {
                val prop = inlineFun(::bar)
                fun bar() = "OK"
            }
            fun main() { println(A().prop) }
            """,
            expectedOutput: "OK\n",
            moduleName: "KUU3371CrossinlineCallableReferenceAnonymousObject"
        )
    }

    @Test func contextCallableReferenceRunsThroughGenericWrapper() throws {
        try compileAndRunKotlin(
            """
            context(c: String) fun ctxLen(): Int = c.length
            fun <T> withCtx(v: String, f: context(String) () -> T): T = with(v) { f() }
            fun main() { println(withCtx("hi", ::ctxLen)) }
            """,
            expectedOutput: "2\n",
            moduleName: "KUU3355ContextCallableReference"
        )
    }

    @Test func stringPlusCallableReferenceConcatenatesCharArrayFoldElements() throws {
        TestStdlibCache.shared.prepare()
        try compileAndRunKotlin(
            """
            fun box() = charArrayOf('O', 'K').fold("", String::plus)
            fun main() { println(box()) }
            """,
            expectedOutput: "OK\n",
            moduleName: "KUU2936StringPlusCallableReferenceFold"
        )
    }

    @Test func innerConstructorReferencePassedToInlineExtensionRetainsOuterCapture() throws {
        try compileAndRunKotlin(
            """
            class A {
                inner class C(val m: String) {
                    fun test(): String {
                        m.f(::C)
                        return m
                    }
                }
            }

            inline fun String.f(g: (String) -> A.C): A.C = g(this)

            fun main() { println(A().C("OK").test()) }
            """,
            expectedOutput: "OK\n",
            moduleName: "KUU3378InnerConstructorReferenceInlineExtension"
        )
    }

    @Test func adaptsVarargAndTrailingDefaultArgumentsAtRuntime() throws {
        try compileAndRunKotlin(
            """
            import kotlin.reflect.KCallable

            fun useArray(factory: (Int, Int) -> Array<Int>): Array<Int> = factory(11, 22)
            fun combine(first: Int = 3, second: Int = 4): Int = first * 10 + second
            fun collect(vararg values: Int) {}
            fun isCallable(value: Any): Boolean = value is KCallable<*>

            fun main() {
                val factory: (Int, Int) -> Array<Int> = ::arrayOf
                val values = useArray(factory)
                println(values[0])
                println(values[1])

                val noArguments: () -> Int = ::combine
                val oneArgument: (Int) -> Int = ::combine
                val packed: (IntArray) -> Unit = ::collect
                println(noArguments())
                println(oneArgument(8))
                println(isCallable(factory))
                println(isCallable(noArguments))
                println(isCallable(packed))
            }
            """,
            expectedOutput: "11\n22\n34\n84\nfalse\nfalse\ntrue\n",
            moduleName: "KUU2098CallableReference"
        )
    }

    @Test func defaultArgumentCallableReferenceRunsThroughGenericFunction() throws {
        try compileAndRunKotlin(
            """
            fun foo(x: String, y: Char = 'K'): String = x + y
            fun <T, U> call(f: (T) -> U, x: T): U = f(x)
            fun main() { println(call(::foo, "O")) }
            """,
            expectedOutput: "OK\n",
            moduleName: "KUU3350DefaultArgumentCallableReferenceThroughGenericFunction"
        )
    }

    @Test func virtualStringVarargCallableReferenceUsesPackedArrayABI() throws {
        try compileAndRunKotlin(
            """
            open class VirtualWords { open fun take(vararg values: String): String = "base:" + values.size }
            class DerivedWords : VirtualWords() { override fun take(vararg values: String): String = "derived:" + values.size }

            fun main() {
                val receiver: VirtualWords = DerivedWords()
                val scalar: (String) -> String = receiver::take
                println(scalar("x"))
            }
            """,
            expectedOutput: "derived:1\n",
            moduleName: "KUUVirtualStringVarargABI",
            optLevel: .O2
        )
    }

    @Test func importedObjectVarargCallableReferenceAdaptsToSingleArgument() throws {
        try compileAndRunKotlin(
            """
            import Host.foo

            fun withO(fn: (String) -> String): String = fn("O")
            object Host { fun foo(vararg x: String): String = x[0] + "K" }
            fun main() { println(withO(::foo)) }
            """,
            expectedOutput: "OK\n",
            moduleName: "KUU3351ImportedObjectVarargCallableReference"
        )
    }
}
