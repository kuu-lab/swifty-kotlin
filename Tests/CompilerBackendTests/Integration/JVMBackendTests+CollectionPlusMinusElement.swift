#if canImport(Testing)
@testable import CompilerCore
import Testing

extension JVMBackendTests {
    @Test(arguments: [EmitMode.jvmClass, .jvmJar])
    func kuu4697CollectionPlusAndMinusElementMatchKotlinc(mode: EmitMode) throws {
        try withWorkspace { root in
            try runRuntimeParity("""
            fun setAdder(source: Set<Int>): (Int) -> Set<Int> = source::plusElement
            fun listRemover(source: List<Int>): (Int) -> List<Int> = source::minusElement
            fun sequenceAdder(source: Sequence<Int>): (Int) -> Sequence<Int> = source::plusElement

            fun main() {
                val values: Set<Int?> = setOf(1, null, 2, 3)
                println(values.plusElement(8))
                println(values.plusElement(1))
                println(values.minusElement(null))
                println(values.minusElement(9))
                val nested: Set<List<Int>> = setOf(listOf(1))
                println(nested.plusElement(listOf(2, 3)))
                val list: List<Int> = listOf(1, 2, 1)
                println(list.plusElement(4))
                println(list.minusElement(1))
                val iterable: Iterable<String> = listOf("a", "b")
                println(iterable.plusElement("c"))
                println(iterable.minusElement("a"))
                val collection: Collection<Int> = listOf(5)
                println(collection.plusElement(6))
                val lists: List<List<Int>> = listOf(listOf(1))
                println(lists.plusElement(listOf(2)))
                println(sequenceOf(1, 2).plusElement(3).toList())
                println(arrayOf("x").plusElement("y").toList())
                println(setAdder(setOf(1))(2))
                println(listRemover(listOf(1, 2))(1))
                println(sequenceAdder(sequenceOf(7))(8).toList())
            }
            """, expected: "[1, null, 2, 3, 8]\n[1, null, 2, 3]\n[1, 2, 3]\n[1, null, 2, 3]\n[[1], [2, 3]]\n[1, 2, 1, 4]\n[2, 1]\n[a, b, c]\n[b]\n[5, 6]\n[[1], [2]]\n[1, 2, 3]\n[x, y]\n[1, 2]\n[2]\n[7, 8]\n", mode: mode, root: root)
        }
    }
}
#endif
