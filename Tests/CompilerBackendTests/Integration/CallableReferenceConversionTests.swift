#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct CallableReferenceConversionTests {
    @Test func directlyTypedSuspendReferencesMaterializeAdapters() throws {
        try assertKotlinOutput("""
        import kotlin.coroutines.*
        fun identity(value: Int): Int = value
        fun defaulted(value: Int = 42): Int = value
        fun launch(block: suspend () -> Int) {
            block.startCoroutine(object: Continuation<Int> {
                override val context: CoroutineContext = EmptyCoroutineContext
                override fun resumeWith(result: Result<Int>) { println(result.getOrThrow()) }
            })
        }
        fun main() {
            val direct: suspend (Int) -> Int = ::identity
            val omitted: suspend () -> Int = ::defaulted
            val unit: (Int) -> Unit = ::identity
            println(direct is kotlin.reflect.KFunction<*>)
            println(omitted is kotlin.reflect.KFunction<*>)
            println(unit is kotlin.reflect.KFunction<*>)
            launch { direct(7) }
            launch(omitted)
        }
        """, moduleName: "CallableReferenceConversions", expected: "false\nfalse\nfalse\n7\n42\n")
    }

    @Test func inheritedCallableReferencesKeepReceiverScopedDefaults() throws {
        try assertKotlinOutput("""
        interface Api<T> { fun number(input: T, suffix: String = "!"): String }
        open class IntBase { fun number(input: Int, suffix: String): String = "$input$suffix" }
        class IntLeaf: IntBase(), Api<Int>
        fun main() {
            val bound: (Int) -> String = IntLeaf()::number
            val unbound: (IntLeaf, Int) -> String = IntLeaf::number
            println(bound(9))
            println(unbound(IntLeaf(), 10))
        }
        """, moduleName: "InheritedCallableReferenceDefaults", expected: "9!\n10!\n")
    }
}
#endif
