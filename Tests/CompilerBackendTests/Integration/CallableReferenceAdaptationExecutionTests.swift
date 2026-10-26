import Testing
import TestStdlibCache

@Suite(.serialized)
struct CallableReferenceAdaptationExecutionTests {
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
