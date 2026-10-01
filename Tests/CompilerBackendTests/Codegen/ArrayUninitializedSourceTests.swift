@testable import CompilerCore
@testable import CompilerBackend
import Testing

@Suite
struct ArrayUninitializedSourceTests {
    @Test
    func uninitializedArraySupportsWritesEmptyAndNegativeCapacity() throws {
        try assertKotlinOutput("""
        @file:Suppress("INVISIBLE_REFERENCE", "INVISIBLE_MEMBER")
        import kotlin.collections.arrayOfUninitializedElements
        
        fun main() {
            val values: Array<String?> = arrayOfUninitializedElements(2)
            values[0] = "ready"
            values[1] = null
            println(values.size)
            println(values.toList())
            val empty: Array<Int> = arrayOfUninitializedElements(0)
            println(empty.size)
            try { arrayOfUninitializedElements<Any>(-1) } catch (e: IllegalArgumentException) { println(e.message) }
            println(arrayListOf<Int>())
            println(arrayListOf(3, 1, 3))
        }
        """, moduleName: "ArrayUninitializedSource", expected: "2\n[ready, null]\n0\ncapacity must be non-negative.\n[]\n[3, 1, 3]\n")
    }
}
