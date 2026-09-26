#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct CodegenBackendForEachNonLocalReturnTests {

    @Test
    func testListForEachNonLocalReturnWithDefaultStdlib() throws {
        let source = """
        fun search(values: List<Int>): Int {
            values.forEach {
                if (it > 1) return it
            }
            return -1
        }

        fun filteredSearch(values: List<Int>): Int {
            values.filter { it > 0 }.forEach {
                if (it > 1) return it
            }
            return -1
        }

        fun main() {
            println(search(listOf(1, 2, 3)))
            println(filteredSearch(listOf(1, 2, 3)))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ListForEachNonLocalReturnDefault",
            expected: "2\n2\n"
        )
    }

    @Test
    func testSourceBackedForEachNonLocalReturns() throws {
        let source = """
        fun setSearch(values: Set<Int>): Int {
            values.forEach {
                if (it > 1) return it
            }
            return -1
        }

        fun intArraySearch(values: IntArray): Int {
            values.forEach {
                if (it > 1) return it
            }
            return -1
        }

        fun indexedSearch(values: List<Int>): Int {
            values.forEachIndexed { _, value ->
                if (value > 1) return value
            }
            return -1
        }

        fun main() {
            println(setSearch(setOf(1, 2, 3)))
            println(intArraySearch(intArrayOf(1, 2, 3)))
            println(indexedSearch(listOf(1, 2, 3)))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ForEachNonLocalReturnSource",
            expected: "2\n2\n2\n",
            allowDefaultStdlibLibrary: false
        )
    }
}
#endif
