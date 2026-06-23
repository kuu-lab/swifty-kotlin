@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCompilesMutableCollectionEdgeCases() throws {
        let source = """
        fun main() {
            val zipped = listOf(1, 2, 3).zip(listOf("a", "b"))
            println(zipped)
            println(zipped.unzip().first)
            println(zipped.unzip().second)

            val map = mutableMapOf("a" to 1)
            map.putAll(mutableMapOf("b" to 2, "c" to 3))
            println(map.keys.toList())
            println(map.values.toList())

            val numbers = mutableListOf(1, 2, 3, 4, 5)
            numbers.removeAll(listOf(2, 5))
            println(numbers)

            numbers.retainAll(listOf(1, 4))
            println(numbers)

            val subtractable = mutableListOf(1, 2, 2, 3)
            subtractable -= 2
            subtractable -= listOf(3)
            println(subtractable)

            val mutableSet = mutableSetOf(1, 2, 3)
            mutableSet -= 2
            mutableSet -= listOf(3)
            println(mutableSet)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "MutableCollectionEdgeCases",
            expected:
                """
                [(1, a), (2, b)]
                [1, 2]
                [a, b]
                [a, b, c]
                [1, 2, 3]
                [1, 3, 4]
                [1, 4]
                [1, 2]
                [1]
                """ + "\n"
        )
    }
}

