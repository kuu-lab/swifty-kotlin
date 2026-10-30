@testable import CompilerCore
import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [false, true], [0, 2])
    func nonNullIdentityNullFoldPreservesOperands(fromArtifact: Bool, optimization: Int) throws {
        let source = try diffCaseSource("non_null_identity_null_fold.kt", file: #filePath)
        try compileAndRunKotlin(
            source,
            expectedOutput: "true\ntrue\nfalse\nfalse\n4\ntrue\nfalse\nfalse\ntrue\ntrue\nfalse\n6\n",
            moduleName: "NonNullIdentityNullFold",
            allowDefaultStdlibLibrary: fromArtifact,
            optLevel: try #require(OptimizationLevel(rawValue: optimization)),
            expectedStderr: ""
        )
    }
}
