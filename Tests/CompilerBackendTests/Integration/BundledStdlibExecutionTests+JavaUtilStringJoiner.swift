@testable import CompilerCore
import Testing

extension BundledStdlibExecutionTests {
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
