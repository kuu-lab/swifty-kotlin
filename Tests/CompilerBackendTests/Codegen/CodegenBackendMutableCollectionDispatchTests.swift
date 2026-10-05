@testable import CompilerCore
@testable import CompilerBackend
import Testing

@Suite
struct CodegenBackendMutableCollectionDispatchTests {
    @Test(arguments: [true, false])
    func mutationExceptionsReachCatch(useArtifact: Bool) throws {
        let source = """
        class ThrowingCollection : MutableCollection<Int> {
            val failure = IllegalStateException("override")
            override val size: Int get() = 0
            override fun isEmpty(): Boolean = true
            override fun contains(element: Int): Boolean = false
            override fun containsAll(elements: Collection<Int>): Boolean = elements.isEmpty()
            override fun iterator(): MutableIterator<Int> = mutableListOf<Int>().iterator()
            override fun add(element: Int): Boolean { throw failure }
            override fun addAll(elements: Collection<Int>): Boolean { throw failure }
            override fun remove(element: Int): Boolean { throw failure }
            override fun removeAll(elements: Collection<Int>): Boolean { throw failure }
            override fun retainAll(elements: Collection<Int>): Boolean { throw failure }
            override fun clear() { throw failure }
        }

        fun main() {
            val concrete = ThrowingCollection()
            val collection: MutableCollection<Int> = concrete
            try { collection.remove(1); println("missed-remove") }
            catch (e: IllegalArgumentException) { println("wrong-type") }
            catch (e: IllegalStateException) { println("remove:" + (e === concrete.failure)) }
            try { collection.clear(); println("missed-clear") }
            catch (e: IllegalStateException) { println("clear:" + e.message) }
            try { collection.add(1); println("missed-add") }
            catch (e: IllegalStateException) { println("add:" + e.message) }
            try { collection.addAll(emptyList<Int>()); println("missed-addAll") }
            catch (e: IllegalStateException) { println("addAll:" + e.message) }
            try { collection.removeAll(emptyList<Int>()); println("missed-removeAll") }
            catch (e: IllegalStateException) { println("removeAll:" + e.message) }
            try {
                try { collection.retainAll(emptyList<Int>()) }
                catch (e: IllegalStateException) { throw e }
            } catch (e: IllegalStateException) { println("retainAll:" + (e === concrete.failure)) }
            println("continued")
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "MutableCollectionThrowingDispatch",
            expected: "remove:true\nclear:override\nadd:override\naddAll:override\nremoveAll:override\nretainAll:true\ncontinued\n",
            allowDefaultStdlibLibrary: useArtifact
        )
    }

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
