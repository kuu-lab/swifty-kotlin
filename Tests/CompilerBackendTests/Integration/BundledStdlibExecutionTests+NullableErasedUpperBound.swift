@testable import CompilerCore
@testable import CompilerTestSupport
import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [false, true], [0, 2])
    func nullableErasedUpperBoundsPreserveNullAndCheckValues(fromArtifact: Bool, optimization: Int) throws {
        let source = try diffCaseSource("nullable_erased_upper_bound.kt", file: #filePath)
        try compileAndRunKotlin(
            source,
            expectedOutput: "null\n7\nwrong type\nnull\nnull\n1\n3\n",
            moduleName: "NullableErasedUpperBound",
            allowDefaultStdlibLibrary: fromArtifact,
            optLevel: try #require(OptimizationLevel(rawValue: optimization)),
            expectedStderr: ""
        )
    }
}
