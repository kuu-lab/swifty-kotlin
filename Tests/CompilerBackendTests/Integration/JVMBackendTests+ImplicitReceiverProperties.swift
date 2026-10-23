#if canImport(Testing)
@testable import CompilerCore
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func implicitReceiverMemberPropertiesAndIteratorCall(mode: EmitMode) throws {
        try withWorkspace { root in
            try runRuntimeParity("""
            fun List<Int>.implicitSize(): Int = size
            fun List<Int>.implicitIteratorValue(): Int = iterator().next()
            fun MutableList<Int>.implicitMutableSize(): Int = size
            fun Set<Int>.implicitSetSize(): Int = size
            fun Collection<Int>.implicitCollectionSize(): Int = size
            fun Map<String, Int>.implicitSize(): Int = size
            fun IntArray.implicitSize(): Int = size
            fun String.implicitLength(): Int = length
            fun List<Int>.shadowedSize(): Int { val size = 9; return size }
            fun main() {
                println(listOf(1, 2).implicitSize())
                println(listOf(7, 8).implicitIteratorValue())
                println(mapOf("a" to 1).implicitSize())
                println(mutableListOf(3, 4).implicitMutableSize())
                println(setOf(5, 6).implicitSetSize())
                val collection: Collection<Int> = listOf(8, 9, 10)
                println(collection.implicitCollectionSize())
                println(intArrayOf(3, 4, 5).implicitSize())
                println("a😀".implicitLength())
                println(listOf(1).shadowedSize())
            }
            """, expected: "2\n7\n1\n2\n2\n3\n3\n3\n9\n", mode: mode, root: root)
        }
    }
}
#endif
