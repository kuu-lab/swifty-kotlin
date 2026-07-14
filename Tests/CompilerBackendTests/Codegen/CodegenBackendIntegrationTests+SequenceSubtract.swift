@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    // Candidate-only: Sequence.subtract (STDLIB-SEQ-FN-115) has no JVM kotlin-stdlib equivalent
    // (subtract is an Iterable extension, and Sequence does not implement Iterable), so this
    // isn't verified via diff_kotlinc.sh.
    func testCodegenSequenceSubtractHandlesListSetAndEmptyReceivers() throws {
        let source = """
        fun main() {
            println(sequenceOf(1, 2, 2, 3, 4).subtract(listOf(2, 4, 2)))
            println(sequenceOf("a", "b", "a", "c").subtract(setOf("a")))
            println(emptySequence<Int>().subtract(listOf(1)))
        }
        """

        try assertKotlinOutput(source, moduleName: "SequenceSubtractRuntime", expected: "[1, 3]\n[b, c]\n[]\n")
    }
}

