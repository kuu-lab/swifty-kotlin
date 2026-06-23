@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenListFlatMapBasic() throws {
        let source = """
        fun main() {
            val values = listOf(1, 2, 3)
            val result = values.flatMap { listOf(it, it * 10) }
            println(result)
        }
        """

        try assertKotlinOutput(source, moduleName: "CollectionFlatMapBasic", expected: "[1, 10, 2, 20, 3, 30]\n")
    }

    func testCodegenListFlatMapWithEmptyInput() throws {
        let source = """
        fun main() {
            val values = emptyList<Int>()
            val result = values.flatMap { listOf(it, it * 10) }
            println(result)
            println(result.size)
        }
        """

        try assertKotlinOutput(source, moduleName: "CollectionFlatMapEmptyInput", expected: "[]\n0\n")
    }

    func testCodegenListFlatMapWithConditionalEmptySubList() throws {
        let source = """
        fun main() {
            val values = listOf(1, 2, 3, 4, 5)
            val result = values.flatMap { if (it % 2 == 0) listOf(it) else listOf<Int>() }
            println(result)
        }
        """

        try assertKotlinOutput(source, moduleName: "CollectionFlatMapConditionalEmpty", expected: "[2, 4]\n")
    }

    func testCodegenListFlatMapIndexed() throws {
        let source = """
        fun main() {
            val values = listOf(10, 20, 30)
            val result = values.flatMapIndexed { index, value -> listOf(index, value) }
            println(result)
        }
        """

        try assertKotlinOutput(source, moduleName: "CollectionFlatMapIndexed", expected: "[0, 10, 1, 20, 2, 30]\n")
    }
}

