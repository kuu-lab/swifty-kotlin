#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Testing

@Suite
struct CodegenBackendCustomListBridgeTests {
    @Test func listMembersDispatchToKotlinImplementation() throws {
        let source = """
        interface CustomList : List<Int>

        class CustomListImpl(private val backing: List<Int>) : CustomList {
            override val size: Int get() = 42
            override fun isEmpty(): Boolean = false
            override fun iterator(): Iterator<Int> = backing.iterator()
            override fun contains(element: Int): Boolean = backing.contains(element)
            override fun containsAll(elements: Collection<Int>): Boolean = backing.containsAll(elements)
            override fun get(index: Int): Int = backing[index]
            override fun indexOf(element: Int): Int = backing.indexOf(element)
            override fun lastIndexOf(element: Int): Int = backing.lastIndexOf(element)
            override fun listIterator(): ListIterator<Int> = backing.listIterator()
            override fun listIterator(index: Int): ListIterator<Int> = backing.listIterator(index)
            override fun subList(fromIndex: Int, toIndex: Int): List<Int> = backing.subList(fromIndex, toIndex)
        }

        fun main() {
            val concrete: CustomList = CustomListImpl(listOf(1, 2, 3))
            val list: List<Int> = concrete
            val collection: Collection<Int> = concrete
            println(concrete.size)
            println(list.size)
            println(collection.size)
            println(concrete.isEmpty())
            println(list.isEmpty())
            println(collection.isEmpty())
            println(concrete[1])
            println(list[1])
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "CustomListBridge",
            expected: "42\n42\n42\nfalse\nfalse\nfalse\n2\n2\n"
        )
    }
}
#endif
