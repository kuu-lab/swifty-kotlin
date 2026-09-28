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
            println(concrete.listIterator(1).next())
            println(list.listIterator(2).next())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "CustomListBridge",
            expected: "42\n42\n42\nfalse\nfalse\nfalse\n2\n2\n2\n3\n"
        )
    }

    @Test func mutableListSubListPreservesSourceView() throws {
        let source = """
        class CustomMutableList : AbstractMutableList<Int>() {
            private val backing = mutableListOf(1, 2, 3)
            override val size: Int get() = backing.size
            override fun get(index: Int): Int = backing[index]
            override fun set(index: Int, element: Int): Int = backing.set(index, element)
            override fun add(index: Int, element: Int) { backing.add(index, element) }
            override fun removeAt(index: Int): Int = backing.removeAt(index)
        }

        fun main() {
            val list: MutableList<Int> = CustomMutableList()
            val sub: MutableList<Int> = list.subList(1, 3)
            println(sub[0])
            sub[0] = 42
            println(list[1])
            println(list.listIterator(1).next())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "CustomMutableListBridge",
            expected: "2\n42\n42\n"
        )
    }
}
#endif
