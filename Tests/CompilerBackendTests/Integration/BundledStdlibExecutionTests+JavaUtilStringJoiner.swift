@testable import CompilerCore
import Testing

extension BundledStdlibExecutionTests {
    // KUU-4450: merge must append the other joiner's elements re-joined with
    // ITS delimiter (prefix/suffix excluded) as a single element, matching
    // the JDK StringJoiner.compactElts contract.
    @Test
    func testStringJoinerMergeCollapsesElementsLikeJvm() throws {
        try compileAndRunKotlin(
            try diffCaseSource("kuu4450_stringjoiner_merge.kt", file: #filePath),
            expectedOutput: """
            a, b, x,y
            p|q|r|s
            m-n
            keep
            i+j
            [x,y]
            [x,y,z]
            3
            1;2.3;4

            """
        )
    }
}
