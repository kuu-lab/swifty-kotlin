import XCTest
@testable import CompilerCore
@testable import CompilerBackend

extension CodegenBackendIntegrationTests {
    func testCodegenListIsNotEmptyUsesRuntimeHelper() throws {
        let source = """
        fun main() {
            println(listOf(1).isNotEmpty())
            println(emptyList<Int>().isNotEmpty())
        }
        """

        try assertKotlinOutput(source, moduleName: "ListIsNotEmptyRuntime", expected: "true\nfalse\n")
    }
}

