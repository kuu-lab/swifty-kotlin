@testable import CompilerCore
@testable import CompilerBackend
import Testing

@Suite
struct CodegenBackendMutableCollectionDispatchTests {
    @Test(arguments: [true, false])
    func mutationsReachSourceOverrides(useArtifact: Bool) throws {
        let source = """
        class TrackedCollection : MutableCollection<Int> {
            val backing = mutableListOf(1, 2, 2, 3)
            var calls: String = ""
            override val size: Int get() = backing.size
            override fun isEmpty(): Boolean = backing.isEmpty()
            override fun contains(element: Int): Boolean = backing.contains(element)
            override fun containsAll(elements: Collection<Int>): Boolean = backing.containsAll(elements)
            override fun iterator(): MutableIterator<Int> = backing.iterator()
            override fun add(element: Int): Boolean { calls += "a"; return backing.add(element) }
            override fun remove(element: Int): Boolean { calls += "r"; return backing.remove(element) }
            override fun addAll(elements: Collection<Int>): Boolean { calls += "A"; return backing.addAll(elements) }
            override fun removeAll(elements: Collection<Int>): Boolean { calls += "R"; return backing.removeAll(elements) }
            override fun retainAll(elements: Collection<Int>): Boolean { calls += "T"; return backing.retainAll(elements) }
            override fun clear() { calls += "c"; backing.clear() }
        }
        
        fun main() {
            val concrete = TrackedCollection()
            val values: MutableCollection<Int> = concrete
            println(values.add(4))
            println(values.remove(2))
            println(concrete.backing)
            println(values.remove(99))
            println(values.addAll(listOf(5, 6)))
            println(values.addAll(emptyList<Int>()))
            println(values.removeAll(listOf(2, 5)))
            println(values.removeAll(listOf(99)))
            println(concrete.backing)
            println(values.retainAll(listOf(1, 6)))
            println(values.retainAll(listOf(1, 6)))
            println(concrete.backing)
            val iterator = values.iterator()
            println(iterator.next())
            iterator.remove()
            println(concrete.backing)
            values.clear()
            println(concrete.backing)
            println(concrete.calls)
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "MutableCollectionDispatch",
            expected: "true\ntrue\n[1, 2, 3, 4]\nfalse\ntrue\nfalse\ntrue\nfalse\n[1, 3, 4, 6]\ntrue\nfalse\n[1, 6]\n1\n[6]\n[]\narrAARRTTc\n",
            allowDefaultStdlibLibrary: useArtifact
        )
    }
}
