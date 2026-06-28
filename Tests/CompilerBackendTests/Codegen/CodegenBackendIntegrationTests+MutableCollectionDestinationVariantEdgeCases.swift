@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {

    func testFilterToAppendsToDestination() throws {
        let source = """
        fun main() {
            val src = listOf(1, 2, 3, 4, 5)
            val dest = mutableListOf(0)
            val result = src.filterTo(dest) { it % 2 == 0 }
            println(result === dest)
            println(result)
        }
        """
        try assertKotlinCompilesToKIR(source, moduleName: "STDLIB021_01")
    }

    func testFilterToEmptySourceLeavesDestination() throws {
        let source = """
        fun main() {
            val src = emptyList<Int>()
            val dest = mutableListOf(42)
            val result = src.filterTo(dest) { it > 0 }
            println(result.size)
            println(result[0])
        }
        """
        try assertKotlinCompilesToKIR(source, moduleName: "STDLIB021_02")
    }

    func testMapToAppendsToDestination() throws {
        let source = """
        fun main() {
            val src = listOf(1, 2, 3)
            val dest = mutableListOf("pre")
            val result = src.mapTo(dest) { it.toString() }
            println(result === dest)
            println(result)
        }
        """
        try assertKotlinCompilesToKIR(source, moduleName: "STDLIB021_03")
    }

    func testMapToEmptySourceLeavesDestination() throws {
        let source = """
        fun main() {
            val src = emptyList<Int>()
            val dest = mutableListOf("existing")
            src.mapTo(dest) { it.toString() }
            println(dest.size)
            println(dest[0])
        }
        """
        try assertKotlinCompilesToKIR(source, moduleName: "STDLIB021_04")
    }

    func testFlatMapToAppendsToDestination() throws {
        let source = """
        fun main() {
            val src = listOf(listOf(1, 2), listOf(3, 4))
            val dest = mutableListOf(0)
            val result = src.flatMapTo(dest) { it }
            println(result === dest)
            println(result)
        }
        """
        try assertKotlinCompilesToKIR(source, moduleName: "STDLIB021_05")
    }

    func testFlatMapToEmptySourceLeavesDestination() throws {
        let source = """
        fun main() {
            val src = emptyList<List<Int>>()
            val dest = mutableListOf(99)
            src.flatMapTo(dest) { it }
            println(dest.size)
            println(dest[0])
        }
        """
        try assertKotlinCompilesToKIR(source, moduleName: "STDLIB021_06")
    }

    func testAssociateToPopulatesDestination() throws {
        let source = """
        fun main() {
            val src = listOf("a", "bb", "ccc")
            val dest = mutableMapOf<String, Int>()
            val result = src.associateTo(dest) { it to it.length }
            println(result === dest)
            println(result["a"])
            println(result["bb"])
            println(result["ccc"])
        }
        """
        try assertKotlinCompilesToKIR(source, moduleName: "STDLIB021_07")
    }

    func testAssociateToOverwritesDuplicateKey() throws {
        let source = """
        fun main() {
            val src = listOf("first", "second")
            val dest = mutableMapOf("key" to 0)
            src.associateTo(dest) { "key" to it.length }
            println(dest["key"])
        }
        """
        try assertKotlinCompilesToKIR(source, moduleName: "STDLIB021_08")
    }

    func testAssociateByToPopulatesDestination() throws {
        let source = """
        fun main() {
            val src = listOf("apple", "banana", "cherry")
            val dest = mutableMapOf<Int, String>()
            val result = src.associateByTo(dest) { it.length }
            println(result === dest)
            println(result[5])
            println(result[6])
        }
        """
        try assertKotlinCompilesToKIR(source, moduleName: "STDLIB021_09")
    }

    func testAssociateByToWithValueTransform() throws {
        let source = """
        fun main() {
            val src = listOf("apple", "banana")
            val dest = mutableMapOf<Int, String>()
            src.associateByTo(dest, { it.length }, { it.uppercase() })
            println(dest[5])
            println(dest[6])
        }
        """
        try assertKotlinCompilesToKIR(source, moduleName: "STDLIB021_10")
    }

    func testAssociateByToOverwritesDuplicateKey() throws {
        let source = """
        fun main() {
            val src = listOf("abc", "def")
            val dest = mutableMapOf<Int, String>()
            src.associateByTo(dest) { it.length }
            println(dest[3])
        }
        """
        try assertKotlinCompilesToKIR(source, moduleName: "STDLIB021_11")
    }

    func testAssociateWithToPopulatesDestination() throws {
        let source = """
        fun main() {
            val src = listOf(1, 2, 3)
            val dest = mutableMapOf<Int, Int>()
            val result = src.associateWithTo(dest) { it * it }
            println(result === dest)
            println(result[1])
            println(result[2])
            println(result[3])
        }
        """
        try assertKotlinCompilesToKIR(source, moduleName: "STDLIB021_12")
    }

    func testAssociateWithToRetainsExistingEntries() throws {
        let source = """
        fun main() {
            val src = listOf(2, 3)
            val dest = mutableMapOf(1 to 100)
            src.associateWithTo(dest) { it * it }
            println(dest[1])
            println(dest[2])
            println(dest[3])
        }
        """
        try assertKotlinCompilesToKIR(source, moduleName: "STDLIB021_13")
    }

    func testGroupByToPopulatesDestination() throws {
        let source = """
        fun main() {
            val src = listOf(1, 2, 3, 4, 5, 6)
            val dest = mutableMapOf<String, MutableList<Int>>()
            val result = src.groupByTo(dest) { if (it % 2 == 0) "even" else "odd" }
            println(result === dest)
            println(result["even"])
            println(result["odd"])
        }
        """
        try assertKotlinCompilesToKIR(source, moduleName: "STDLIB021_14")
    }

    func testGroupByToAppendsToBuckets() throws {
        let source = """
        fun main() {
            val first = listOf(1, 3)
            val second = listOf(5, 7)
            val dest = mutableMapOf<String, MutableList<Int>>()
            first.groupByTo(dest) { "odd" }
            second.groupByTo(dest) { "odd" }
            println(dest["odd"])
        }
        """
        try assertKotlinCompilesToKIR(source, moduleName: "STDLIB021_15")
    }

    func testGroupByToEmptySourceLeavesDestination() throws {
        let source = """
        fun main() {
            val src = emptyList<Int>()
            val dest = mutableMapOf("existing" to mutableListOf(1))
            src.groupByTo(dest) { "key" }
            println(dest["existing"])
        }
        """
        try assertKotlinCompilesToKIR(source, moduleName: "STDLIB021_16")
    }

    func testGroupByToWithValueTransform() throws {
        let source = """
        fun main() {
            val src = listOf("apple", "avocado", "banana")
            val dest = mutableMapOf<Char, MutableList<Int>>()
            src.groupByTo(dest, { it[0] }, { it.length })
            println(dest['a'])
            println(dest['b'])
        }
        """
        try assertKotlinCompilesToKIR(source, moduleName: "STDLIB021_17")
    }

    func testPartitionSplitsElements() throws {
        let source = """
        fun main() {
            val src = listOf(1, 2, 3, 4, 5)
            val (evens, odds) = src.partition { it % 2 == 0 }
            println(evens)
            println(odds)
        }
        """
        try assertKotlinCompilesToKIR(source, moduleName: "STDLIB021_18")
    }

    func testPartitionEmptySource() throws {
        let source = """
        fun main() {
            val src = emptyList<Int>()
            val (yes, no) = src.partition { it > 0 }
            println(yes.size)
            println(no.size)
        }
        """
        try assertKotlinCompilesToKIR(source, moduleName: "STDLIB021_19")
    }

    func testPartitionAllMatch() throws {
        let source = """
        fun main() {
            val src = listOf(2, 4, 6)
            val (evens, odds) = src.partition { it % 2 == 0 }
            println(evens)
            println(odds.size)
        }
        """
        try assertKotlinCompilesToKIR(source, moduleName: "STDLIB021_20")
    }

    func testToCollectionAppendsToDestination() throws {
        let source = """
        fun main() {
            val src = listOf(3, 4, 5)
            val dest = mutableListOf(1, 2)
            val result = src.toCollection(dest)
            println(result === dest)
            println(result)
        }
        """
        try assertKotlinCompilesToKIR(source, moduleName: "STDLIB021_21")
    }

    func testToCollectionEmptySourceLeavesDestination() throws {
        let source = """
        fun main() {
            val src = emptyList<Int>()
            val dest = mutableListOf(1)
            src.toCollection(dest)
            println(dest.size)
            println(dest[0])
        }
        """
        try assertKotlinCompilesToKIR(source, moduleName: "STDLIB021_22")
    }

    func testToCollectionIntoMutableSet() throws {
        let source = """
        fun main() {
            val src = listOf(1, 2, 2, 3, 3, 3)
            val dest = mutableSetOf<Int>()
            src.toCollection(dest)
            println(dest.size)
            println(dest.contains(1))
            println(dest.contains(2))
            println(dest.contains(3))
        }
        """
        try assertKotlinCompilesToKIR(source, moduleName: "STDLIB021_23")
    }

    func testToMutableListReturnsIndependentCopy() throws {
        let source = """
        fun main() {
            val src = listOf(1, 2, 3)
            val copy = src.toMutableList()
            copy.add(4)
            println(src.size)
            println(copy.size)
        }
        """
        try assertKotlinCompilesToKIR(source, moduleName: "STDLIB021_24")
    }

    func testToMutableListFromEmpty() throws {
        let source = """
        fun main() {
            val src = emptyList<Int>()
            val copy = src.toMutableList()
            println(copy.isEmpty())
            copy.add(1)
            println(copy.size)
        }
        """
        try assertKotlinCompilesToKIR(source, moduleName: "STDLIB021_25")
    }

    func testToMutableSetDeduplicates() throws {
        let source = """
        fun main() {
            val src = listOf(1, 2, 2, 3)
            val set = src.toMutableSet()
            println(set.size)
            set.add(4)
            println(set.size)
        }
        """
        try assertKotlinCompilesToKIR(source, moduleName: "STDLIB021_26")
    }

    func testToMutableSetFromEmpty() throws {
        let source = """
        fun main() {
            val src = emptyList<String>()
            val set = src.toMutableSet()
            println(set.isEmpty())
            set.add("hello")
            println(set.contains("hello"))
        }
        """
        try assertKotlinCompilesToKIR(source, moduleName: "STDLIB021_27")
    }

    func testToMutableMapReturnsMutableCopy() throws {
        let source = """
        fun main() {
            val src = mapOf("a" to 1, "b" to 2)
            val copy = src.toMutableMap()
            copy["c"] = 3
            println(src.size)
            println(copy.size)
            println(copy["c"])
        }
        """
        try assertKotlinCompilesToKIR(source, moduleName: "STDLIB021_28")
    }

    func testToMutableMapFromEmpty() throws {
        let source = """
        fun main() {
            val src = emptyMap<String, Int>()
            val copy = src.toMutableMap()
            println(copy.isEmpty())
            copy["x"] = 10
            println(copy["x"])
        }
        """
        try assertKotlinCompilesToKIR(source, moduleName: "STDLIB021_29")
    }

    func testFilterToPreservesInsertionOrder() throws {
        let source = """
        fun main() {
            val src = listOf(5, 1, 4, 2, 3)
            val dest = mutableListOf<Int>()
            src.filterTo(dest) { it > 2 }
            println(dest)
        }
        """
        try assertKotlinCompilesToKIR(source, moduleName: "STDLIB021_30")
    }

    func testMapToPreservesInsertionOrder() throws {
        let source = """
        fun main() {
            val src = listOf("c", "a", "b")
            val dest = mutableListOf<String>()
            src.mapTo(dest) { it.uppercase() }
            println(dest)
        }
        """
        try assertKotlinCompilesToKIR(source, moduleName: "STDLIB021_31")
    }

    func testAssociateToEmptySourceLeavesDestination() throws {
        let source = """
        fun main() {
            val src = emptyList<String>()
            val dest = mutableMapOf("existing" to 99)
            src.associateTo(dest) { it to it.length }
            println(dest["existing"])
            println(dest.size)
        }
        """
        try assertKotlinCompilesToKIR(source, moduleName: "STDLIB021_32")
    }

    func testFilterToLinkedHashSetPreservesOrder() throws {
        let source = """
        fun main() {
            val src = listOf(3, 1, 4, 1, 5, 9, 2, 6)
            val dest = LinkedHashSet<Int>()
            src.filterTo(dest) { it > 2 }
            println(dest.toList())
        }
        """
        try assertKotlinCompilesToKIR(source, moduleName: "STDLIB021_33")
    }

    func testMapNotNullToFiltersNulls() throws {
        let source = """
        fun main() {
            val src = listOf("1", "abc", "2", "def", "3")
            val dest = mutableListOf<Int>()
            src.mapNotNullTo(dest) { it.toIntOrNull() }
            println(dest)
        }
        """
        try assertKotlinCompilesToKIR(source, moduleName: "STDLIB021_34")
    }

    func testFilterNotNullToAppendsNonNullValues() throws {
        let source = """
        fun main() {
            val src = listOf("a", null, "b", null)
            val dest = mutableListOf<String>()
            val result = src.filterNotNullTo(dest)
            println(result === dest)
            println(result)
        }
        """
        try assertKotlinCompilesToKIR(source, moduleName: "STDLIB021_34_FILTER_NOT_NULL_TO")
    }

    func testFilterNotToAppendsNonMatchingElements() throws {
        let source = """
        fun main() {
            val src = listOf(1, 2, 3, 4, 5)
            val dest = mutableListOf<Int>()
            val result = src.filterNotTo(dest) { it % 2 == 0 }
            println(result === dest)
            println(result)
        }
        """
        try assertKotlinCompilesToKIR(source, moduleName: "STDLIB021_35")
    }

    func testFilterIsInstanceToCollectsTypedElements() throws {
        let source = """
        fun main() {
            val src: List<Any> = listOf(1, "hello", 2, "world", 3.0)
            val dest = mutableListOf<String>()
            src.filterIsInstanceTo(dest)
            println(dest)
        }
        """
        try assertKotlinCompilesToKIR(source, moduleName: "STDLIB021_36")
    }

    func testMapIndexedToAppendsIndexedElements() throws {
        let source = """
        fun main() {
            val src = listOf("a", "b", "c")
            val dest = mutableListOf<String>()
            src.mapIndexedTo(dest) { idx, value -> idx.toString() + ":" + value }
            println(dest)
        }
        """
        try assertKotlinCompilesToKIR(source, moduleName: "STDLIB021_37")
    }

    func testFlatMapIndexedToAppendsElements() throws {
        let source = """
        fun main() {
            val src = listOf("ab", "cd")
            val dest = mutableListOf<String>()
            src.flatMapIndexedTo(dest) { idx, value -> listOf(idx.toString() + value, value.uppercase()) }
            println(dest)
        }
        """
        try assertKotlinCompilesToKIR(source, moduleName: "STDLIB021_38")
    }

    func testGroupingReduceToCompiles() throws {
        let source = """
        fun main() {
            val src = listOf(1, 3, 2)
            val dest = mutableMapOf(1 to 10)
            val result = src.groupingBy { it % 2 }.reduceTo(dest) { key, acc, value ->
                acc * 10 + value + key
            }
            println(result === dest)
            println(result[1])
            println(result[0])
        }
        """
        try assertKotlinCompilesToKIR(source, moduleName: "STDLIB021_39")
    }
}
