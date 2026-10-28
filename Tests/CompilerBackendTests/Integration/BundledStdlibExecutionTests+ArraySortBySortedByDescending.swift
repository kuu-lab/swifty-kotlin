@testable import CompilerCore
import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [false, true], [0, 2])
    func testArraySortBySortedByDescendingAndMinusElement(
        useStdlibLibrary: Bool,
        optimization: Int
    ) throws {
        try compileAndRunKotlin(
            """
            fun main() {
                val values: Array<out Int> = arrayOf(1, 2)
                values.sortBy { -it }
                println(values.toList())
                println(arrayOf(2, 1).sortedByDescending { it })
                println(arrayOf(1, 2).minusElement(1))

                val duplicates = arrayOf(1, 2, 1)
                println(duplicates.minusElement(1))
                println(duplicates.toList())
                println(arrayOf("a", "bb", "c").sortedByDescending { if (it.length == 1) null else it.length })
            }
            """,
            expectedOutput: "[2, 1]\n[2, 1]\n[2]\n[2, 1]\n[1, 2, 1]\n[bb, a, c]\n",
            moduleName: "KUU3050ArraySortAndMinusElement",
            allowDefaultStdlibLibrary: useStdlibLibrary,
            optLevel: try #require(OptimizationLevel(rawValue: optimization)),
            expectedStderr: ""
        )
    }
}
