import XCTest
@testable import CompilerCore
@testable import CompilerBackend

// STDLIB-SEQ-FN-048: Sequence.indexOf
extension CodegenBackendIntegrationTests {
    func testCodegenSequenceIndexOfUsesRuntimeHelper() throws {
        let source = """
        fun main() {
            val values = sequenceOf(10, 20, 10, 30)
            println(values.indexOf(10))
            println(values.indexOf(20))
            println(values.indexOf(99))
        }
        """

        try assertKotlinOutput(source, moduleName: "SequenceIndexOfRuntime", expected: "0\n1\n-1\n")
    }
}

