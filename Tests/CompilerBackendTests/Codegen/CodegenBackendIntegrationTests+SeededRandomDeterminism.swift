@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    /// Regression for KSP-466 residual / BUG-005: `Random`-taking helpers in
    /// the runtime must dispatch through the seeded `Random` object instead
    /// of system entropy, so `shuffled(random)`, `Sequence.shuffled(random)`,
    /// and `IntRange.random(random)` produce deterministic output for a fixed seed.
    func testCodegenSeededRandomCollectionAndRangeHelpersAreDeterministic() throws {
        let source = """
        import kotlin.random.Random

        fun main() {
            val r1 = Random(7)
            val r2 = Random(7)

            val list1 = listOf(1, 2, 3, 4, 5).shuffled(r1)
            val list2 = listOf(1, 2, 3, 4, 5).shuffled(r2)
            println(list1 == list2)

            val seq1 = sequenceOf(1, 2, 3, 4, 5).shuffled(r1).toList()
            val seq2 = sequenceOf(1, 2, 3, 4, 5).shuffled(r2).toList()
            println(seq1 == seq2)

            val range1 = (1..100).random(r1)
            val range2 = (1..100).random(r2)
            println(range1 == range2)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "SeededRandomDeterminism",
            expected:
                """
                true
                true
                true
                """ + "\n"
        )
    }
}
