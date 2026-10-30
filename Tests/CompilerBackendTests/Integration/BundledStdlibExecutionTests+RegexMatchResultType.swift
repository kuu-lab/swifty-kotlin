@testable import CompilerCore
import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [false, true], [0, 2])
    func regexMatchResultsKeepTheirTypeAcrossErasure(fromArtifact: Bool, optimization: Int) throws {
        try compileAndRunKotlin(
            try diffCaseSource("regex_match_result_erased_type.kt", file: #filePath),
            expectedOutput: "true\nfalse\na\na\na\n[a, a]\na\n",
            moduleName: "RegexMatchResultType",
            allowDefaultStdlibLibrary: fromArtifact,
            optLevel: try #require(OptimizationLevel(rawValue: optimization)),
            expectedStderr: ""
        )
    }
}
