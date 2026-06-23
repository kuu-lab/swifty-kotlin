@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenListMapIndexedNotNullToUsesRuntimeHelper() throws {
        let source = """
        fun maybeWord(index: Int, value: String): String? = if (index % 2 == 0) value + index else null

        fun main() {
            val dest = mutableListOf("seed")
            val returned = listOf("a", "bb", "ccc").mapIndexedNotNullTo(dest) { index, value ->
                maybeWord(index, value)
            }
            println(dest)
            println(returned)
            println(dest.size)
        }
        """

        try assertKotlinOutput(source, moduleName: "ListMapIndexedNotNullToRuntime", expected: "[seed, a0, ccc2]\n[seed, a0, ccc2]\n3\n")
    }
}

