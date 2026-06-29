@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenIterableLastUsesRuntimeHelper() throws {
        let source = """
        fun main() {
            val collection: Collection<Int> = listOf(1, 2, 3)
            println(collection.last())

            val iterable: Iterable<String> = setOf("x", "y")
            println(iterable.last())
        }
        """

        try assertKotlinOutput(source, moduleName: "IterableLastRuntime", expected: "3\ny\n")
    }
}

