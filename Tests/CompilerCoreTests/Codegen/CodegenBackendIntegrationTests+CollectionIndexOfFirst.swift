import XCTest
@testable import CompilerCore

extension CodegenBackendIntegrationTests {
    func testCodegenListIndexOfFirstUsesRuntimeHelper() throws {
        let source = """
        fun main() {
            println(listOf(1, 3, 4, 6).indexOfFirst { it % 2 == 0 })
            println(listOf(1, 3, 5).indexOfFirst { it % 2 == 0 })
        }
        """

        try assertKotlinOutput(source, moduleName: "ListIndexOfFirstRuntime", expected: "2\n-1\n")
    }
}

