#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct CodegenBackendRangeReversedForInRegressionTests {

    @Test
    func testIntRangeReversedForInUsesProgressionDirection() throws {
        let source = """
        fun main() {
            for (i in (1..3).reversed()) print(i)
            println()

            val progression = (1..3).reversed()
            for (i in progression) print(i)
            println()

            val range: IntRange = 1..3
            for (i in range.reversed()) print(i)
            println()

            for (i in 3 downTo 1) print(i)
            println()
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "IntRangeReversedForInRegression",
            expected:
                """
                321
                321
                321
                321
                """ + "\n"
        )
    }
}
#endif
