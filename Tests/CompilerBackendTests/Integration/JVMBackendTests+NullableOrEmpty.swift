#if canImport(Testing)
@testable import CompilerCore
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func kuu4696NullableCollectionOrEmptyMatchesKotlinc(mode: EmitMode) throws {
        try withWorkspace { root in
            try runRuntimeParity("""
            fun main() {
                println((null as Set<Int?>?).orEmpty())
                val set: Set<String>? = setOf("a", "b")
                println(set.orEmpty())
                val mutableSet: MutableSet<Int>? = null
                val fromMutable: Set<Int> = mutableSet.orEmpty()
                println(fromMutable.size)
                val collection: Collection<Int>? = listOf(7)
                println(collection.orEmpty())
                val absentCollection: Collection<Int>? = null
                println(absentCollection.orEmpty().isEmpty())
                val list: List<Int>? = listOf(4, 5)
                println(list.orEmpty()[1])
                val absentList: List<Int>? = null
                val emptyList: List<Int> = absentList.orEmpty()
                println(emptyList)
                val map: Map<String, Int>? = mapOf("k" to 1)
                println(map.orEmpty())
                val absentMap: Map<String, Int>? = null
                println(absentMap.orEmpty())
                val sequence: Sequence<Int>? = sequenceOf(1, 2)
                println(sequence.orEmpty().toList())
                val absentSequence: Sequence<Int>? = null
                println(absentSequence.orEmpty().toList())
                val array: Array<String>? = arrayOf("x", "y")
                println(array.orEmpty().size)
                val absentArray: Array<String>? = null
                println(absentArray.orEmpty().size)
                val text: String? = null
                println(text.orEmpty().length)
            }
            """, expected: "[]\n[a, b]\n0\n[7]\ntrue\n5\n[]\n{k=1}\n{}\n[1, 2]\n[]\n2\n0\n0\n", mode: mode, root: root)
        }
    }
}
#endif
