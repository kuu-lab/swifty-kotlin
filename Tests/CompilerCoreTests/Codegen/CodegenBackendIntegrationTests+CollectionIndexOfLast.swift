import XCTest
@testable import CompilerCore

extension CodegenBackendIntegrationTests {
    func testCodegenListIndexOfLastUsesRuntimeHelper() throws {
        let source = """
        fun main() {
            println(listOf(1, 4, 5, 6).indexOfLast { it % 2 == 0 })
            println(listOf(1, 3, 5).indexOfLast { it % 2 == 0 })
        }
        """

        try assertKotlinOutput(source, moduleName: "ListIndexOfLastRuntime", expected: "3\n-1\n")
    }
}

