#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

@Suite
struct CodegenBackendMutableIterablePredicateTests {

    @Test
    func testCodegenMutableIterablePredicateOperationsMutateRuntimeCollections() throws {
        let source = """
        class TrackingIterator(private val values: ArrayList<Int>) : MutableIterator<Int> {
            private var index = 0

            override fun hasNext(): Boolean = index < values.size

            override fun next(): Int = values[index++]

            override fun remove() {
                values.removeAt(--index)
            }
        }

        class TrackingIterable(private val values: ArrayList<Int>) : MutableIterable<Int> {
            override fun iterator(): MutableIterator<Int> = TrackingIterator(values)
        }

        fun main() {
            val list = mutableListOf(1, 2, 3)
            val listIterable: MutableIterable<Int> = list
            println(listIterable.removeAll { it == 2 })
            println(list)

            val set = mutableSetOf(1, 2, 3)
            val setIterable: MutableIterable<Int> = set
            println(setIterable.retainAll { it != 2 })
            println(set)

            val customValues = arrayListOf(1, 2, 3)
            println(TrackingIterable(customValues).removeAll { it == 2 })
            println(customValues)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "MutableIterablePredicate",
            expected:
                """
                true
                [1, 3]
                true
                [1, 3]
                true
                [1, 3]
                """ + "\n"
        )
    }

    @Test
    func testCodegenMutableMapEntriesPredicateOperationsMutateMap() throws {
        let source = """
        fun main() {
            val retained = mutableMapOf(1 to "a", 2 to "b", 3 to "c")
            println(retained.entries.retainAll { it.key == 2 })
            println(retained)

            val removed = mutableMapOf(1 to "a", 2 to "b", 3 to "c")
            println(removed.entries.removeAll { it.value != "b" })
            println(removed)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "MutableMapEntriesPredicate",
            expected:
                """
                true
                {2=b}
                true
                {2=b}
                """ + "\n"
        )
    }

}
#endif
