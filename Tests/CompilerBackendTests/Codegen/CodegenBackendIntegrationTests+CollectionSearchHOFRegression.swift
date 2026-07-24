@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

// KSP-423 regression tests: predicate first/last and Array.contains must lower
// to bundled Kotlin source rather than stale kk_* runtime entries.
extension CodegenBackendIntegrationTests {
    func testCodegenListFirstAndLastPredicateUseSourceImplementation() throws {
        let source = """
        fun main() {
            val nums = listOf(2, 4, 3, 4, 5)
            println(nums.first { it > 3 })
            println(nums.last { it < 4 })
            println(nums.find { it > 3 })
            println(nums.firstOrNull { it > 4 })
            println(nums.lastOrNull { it > 4 })
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ListFirstLastPredicateSource",
            expected: "4\n3\n4\n5\n5\n"
        )
    }

    func testCodegenArrayContainsUsesSourceImplementation() throws {
        let source = """
        fun main() {
            val arr = arrayOf(1, 2, 3)
            println(arr.contains(2))
            println(arr.contains(4))
            println(arr.indexOf(2))
            println(arr.lastIndexOf(2))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ArrayContainsSource",
            expected: "true\nfalse\n1\n1\n"
        )
    }

    func testCodegenListAnyNoneCountUseSourceImplementation() throws {
        let source = """
        fun main() {
            val nums = listOf(1, 2, 3)
            println(nums.any())
            println(nums.none())
            println(nums.count())
            val empty = listOf<Int>()
            println(empty.any())
            println(empty.none())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ListAnyNoneCountSource",
            expected: "true\nfalse\n3\nfalse\ntrue\n"
        )
    }
}
