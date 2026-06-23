@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenIterableJoinToStringUsesRuntimeDefaultsAndNamedArguments() throws {
        let source = """
        fun main() {
            val collection: Collection<Int> = listOf(1, 2, 3)
            println(collection.joinToString())
            println(collection.joinToString(" | "))
            println(collection.joinToString(prefix = "<", postfix = ">"))
            println(collection.joinToString(separator = ":", prefix = "[", postfix = "]"))

            val set: Set<String> = setOf("x", "y")
            println(set.joinToString(";"))
        }
        """

        try assertKotlinOutput(source, moduleName: "IterableJoinToStringRuntime", expected: "1, 2, 3\n1 | 2 | 3\n<1, 2, 3>\n[1:2:3]\nx;y\n")
    }
}

