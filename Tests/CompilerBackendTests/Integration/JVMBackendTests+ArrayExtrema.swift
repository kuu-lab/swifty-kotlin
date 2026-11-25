#if canImport(Testing)
@testable import CompilerCore
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func arrayExtremaMatchKotlinc(mode: EmitMode) throws {
        try withWorkspace { root in
            try runRuntimeParity("""
            private fun <T : Comparable<T>> minimum(values: Array<out T>): T? = values.minOrNull()

            fun main() {
                println(emptyArray<Int>().minOrNull())
                println(emptyArray<Int>().maxOrNull())
                val sortedCandidate = arrayOf(3, -2, 1)
                println(minimum(sortedCandidate))
                println(sortedCandidate.maxOrNull())
                println(arrayOf("pear", "apple", "plum").minOrNull())
                println(arrayOf("pear", "apple", "plum").maxOrNull())
                println(intArrayOf().minOrNull())
                println(intArrayOf().maxOrNull())
                val ints = intArrayOf(9, -2, 5)
                println(ints.minOrNull())
                println(ints.maxOrNull())
                println(arrayOf(2.0f, Float.NaN).minOrNull())
                println(arrayOf(Float.NaN, 2.0f).maxOrNull())
                println(arrayOf(0.0, -0.0).minOrNull())
                println(arrayOf(-0.0, 0.0).maxOrNull())
            }
            """, expected: "null\nnull\n-2\n3\napple\nplum\nnull\nnull\n-2\n9\nNaN\nNaN\n-0.0\n0.0\n", mode: mode, root: root)
        }
    }
}
#endif
