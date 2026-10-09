#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct CodegenBackendSequenceTakeLastTests {

    @Test
    func testCodegenMaterializedSequenceTakeLastHandlesBoundaryAndNegativeCounts() throws {
        let source = """
        fun main() {
            println(sequenceOf(1, 2, 3, 4).toList().takeLast(2))
            println(sequenceOf(1, 2).toList().takeLast(5))
            println(sequenceOf(1, 2).toList().takeLast(0))
            try {
                println(sequenceOf(1, 2).toList().takeLast(-1))
                println("missing-negative")
            } catch (e: IllegalArgumentException) {
                println("negative-takeLast")
            }
        }
        """

        try assertKotlinOutput(source, moduleName: "SequenceTakeLastRuntime", expected: "[3, 4]\n[1, 2]\n[]\nnegative-takeLast\n")
    }
}
#endif
