@testable import CompilerCore
import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [false, true], [0, 2])
    func testCharArraySumOfIntSourceAndArtifact(
        useStdlibLibrary: Bool,
        optimization: Int
    ) throws {
        try compileAndRunKotlin(
            try diffCaseSource("chararray_sumof_int.kt", file: #filePath),
            expectedOutput: "4\n0\n0\n-6\n155\n3\n67,65,66\n-2147483648\n177724\n4\n4\n3\n4\n4\n4\n4\n",
            moduleName: "KUU2002CharArraySumOfInt",
            allowDefaultStdlibLibrary: useStdlibLibrary,
            optLevel: try #require(OptimizationLevel(rawValue: optimization)),
            expectedStderr: ""
        )
    }
}
