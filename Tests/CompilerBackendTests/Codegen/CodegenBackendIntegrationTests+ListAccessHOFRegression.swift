@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

// KSP-424 regression tests: List access helpers must lower to bundled Kotlin
// source rather than stale kk_* runtime entries.
extension CodegenBackendIntegrationTests {
    func testCodegenListGetOrNullAndGetOrElseUseSourceImplementation() throws {
        let source = """
        fun main() {
            val nums = listOf(10, 20, 30)
            println(nums.getOrNull(1))
            println(nums.getOrNull(5))
            println(nums.getOrElse(1) { -1 })
            println(nums.getOrElse(5) { it * 10 })
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ListGetOrNullSource",
            expected: "20\nnull\n20\n50\n"
        )
    }

    func testCodegenListElementAtAndOrNullAndOrElseUseSourceImplementation() throws {
        let source = """
        fun main() {
            val nums = listOf(10, 20, 30)
            println(nums.elementAt(1))
            println(nums.elementAtOrNull(1))
            println(nums.elementAtOrNull(5))
            println(nums.elementAtOrElse(1) { -1 })
            println(nums.elementAtOrElse(5) { it * 10 })
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ListElementAtSource",
            expected: "20\n20\nnull\n20\n50\n"
        )
    }

    func testCodegenListElementAtThrowsOnOutOfBounds() throws {
        let source = """
        fun main() {
            val nums = listOf(10, 20, 30)
            try {
                println(nums.elementAt(5))
            } catch (e: IndexOutOfBoundsException) {
                println("caught")
            }
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ListElementAtThrows",
            expected: "caught\n"
        )
    }

    func testCodegenListSingleAndSingleOrNullUseSourceImplementation() throws {
        let source = """
        fun main() {
            val one = listOf(42)
            println(one.single())
            println(one.singleOrNull())
            val nums = listOf(10, 20, 30)
            println(nums.singleOrNull())
            println(nums.single { it > 25 })
            println(nums.singleOrNull { it > 25 })
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ListSingleSource",
            expected: "42\n42\nnull\n30\n30\n"
        )
    }

    func testCodegenListFirstAndLastUseSourceImplementation() throws {
        let source = """
        fun main() {
            val nums = listOf(10, 20, 30)
            println(nums.first())
            println(nums.last())
            println(nums.first { it > 15 })
            println(nums.last { it < 25 })
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ListFirstLastSource",
            expected: "10\n30\n20\n20\n"
        )
    }
}
