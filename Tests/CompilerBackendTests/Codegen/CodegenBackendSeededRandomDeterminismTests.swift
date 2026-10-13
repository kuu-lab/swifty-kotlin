#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct CodegenBackendSeededRandomDeterminismTests {

    @Test
    func testCodegenSeededIntRangeRandomMatchesKotlinValue() throws {
        let source = """
        import kotlin.random.Random

        fun main() {
            println((1..100).random(Random(42)))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "SeededIntRangeRandomParity",
            expected: "34\n"
        )
    }

    @Test
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
#endif
