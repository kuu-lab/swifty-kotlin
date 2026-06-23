@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenListSingleOrNullUsesRuntimeHelper() throws {
        let source = """
        fun printSingleOrNull(values: List<Int>) {
            println(values.singleOrNull() ?: -1)
        }

        fun main() {
            printSingleOrNull(listOf(42))
            printSingleOrNull(emptyList<Int>())
            printSingleOrNull(listOf(1, 2))

            println(listOf("only").singleOrNull() ?: "missing")
            println(emptyList<String>().singleOrNull() ?: "missing")
            println(listOf("a", "b").singleOrNull() ?: "missing")
        }
        """

        try assertKotlinOutput(source, moduleName: "CollectionSingleOrNull", expected: "42\n-1\n-1\nonly\nmissing\nmissing\n")
    }
}

