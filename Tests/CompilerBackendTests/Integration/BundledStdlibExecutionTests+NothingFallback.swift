@testable import CompilerCore
import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [false, true], [0, 2])
    func resultNothingCanReturnConcreteFallback(fromArtifact: Bool, optimization: Int) throws {
        let source = try diffCaseSource("result_nothing_get_or_else.kt", file: #filePath)
        try compileAndRunKotlin(
            source,
            expectedOutput: "-2\nonf boom\n-4\n",
            moduleName: "ResultNothingFallback",
            allowDefaultStdlibLibrary: fromArtifact,
            optLevel: try #require(OptimizationLevel(rawValue: optimization)),
            expectedStderr: ""
        )
    }
}
