@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
#if canImport(Testing)
import Testing

// STDLIB-SEQ-FN-048: Sequence.indexOf
@Suite(.serialized)
struct CodegenBackendSequenceIndexOfTests {

    @Test
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
#endif
