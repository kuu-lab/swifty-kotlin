@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenListMapUsesRuntimeHelper() throws {
        let source = """
        fun main() {
            val values = listOf(1, 2, 3)
            val offset = 5
            val shifted = values.map { it + offset }
            println(shifted)
            println(shifted.size)

            val words = listOf("a", "bb").map { it + "!" }
            println(words)
        }
        """

        try assertKotlinOutput(source, moduleName: "CollectionMap", expected: "[6, 7, 8]\n3\n[a!, bb!]\n")
    }
}

