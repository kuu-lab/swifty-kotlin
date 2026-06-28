import XCTest
@testable import CompilerCore
@testable import CompilerBackend

extension CodegenBackendIntegrationTests {
    func testCodegenStringIndexOfLastUsesRuntimeHelper() throws {
        let source = """
        fun main() {
            println("abcabc".indexOfLast { it == 'b' })
            println("abcabc".indexOfLast { it == 'z' })
            println("hello".indexOfLast { it == 'l' })
            println("".indexOfLast { it == 'a' })
        }
        """

        try assertKotlinOutput(source, moduleName: "StringIndexOfLastRuntime", expected: "4\n-1\n3\n-1\n")
    }
}

