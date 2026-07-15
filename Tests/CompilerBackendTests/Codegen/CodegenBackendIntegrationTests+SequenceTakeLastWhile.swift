@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    // Candidate-only: Sequence.takeLastWhile (STDLIB-SEQ-FN-121) has no JVM kotlin-stdlib equivalent
    // (takeLastWhile is defined for List only), so this isn't verified via diff_kotlinc.sh.
    func testCodegenSequenceTakeLastWhileHandlesPredicateEdgeCases() throws {
        let source = """
        fun main() {
            println(sequenceOf(1, 3, 4, 2, 5, 6).takeLastWhile { value -> value > 2 })
            println(sequenceOf(1, 2, 3).takeLastWhile { value -> value > 10 })
            println(sequenceOf(4, 5, 6).takeLastWhile { value -> value > 2 })
        }
        """

        try assertKotlinOutput(source, moduleName: "SequenceTakeLastWhileRuntime", expected: "[5, 6]\n[]\n[4, 5, 6]\n")
    }
}

