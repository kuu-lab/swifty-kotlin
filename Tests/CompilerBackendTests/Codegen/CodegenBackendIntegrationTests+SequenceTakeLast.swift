@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    // Candidate-only: Sequence.takeLast (STDLIB-SEQ-FN-120) has no JVM kotlin-stdlib equivalent
    // (takeLast is defined for List only), so this isn't verified via diff_kotlinc.sh.
    func testCodegenSequenceTakeLastHandlesBoundaryAndNegativeCounts() throws {
        let source = """
        fun main() {
            println(sequenceOf(1, 2, 3, 4).takeLast(2))
            println(sequenceOf(1, 2).takeLast(5))
            println(sequenceOf(1, 2).takeLast(0))
            try {
                println(sequenceOf(1, 2).takeLast(-1))
                println("missing-negative")
            } catch (e: IllegalArgumentException) {
                println("negative-takeLast")
            }
        }
        """

        try assertKotlinOutput(source, moduleName: "SequenceTakeLastRuntime", expected: "[3, 4]\n[1, 2]\n[]\nnegative-takeLast\n")
    }
}

