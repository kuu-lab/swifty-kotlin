@testable import CompilerCore
import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [false, true], [0, 2])
    func rangeForEachAllowsNonLocalReturn(fromArtifact: Bool, optimization: Int) throws {
        let source = try diffCaseSource("int_range_foreach_non_local_return.kt", file: #filePath)
        try compileAndRunKotlin(
            source,
            expectedOutput: "range:1\nrange:2\nlist:1\n2\n-1\n3\n3\n-1\n21\n4\nfinally\n2\n",
            moduleName: "KUU3993RangeForEachNonLocalReturn",
            allowDefaultStdlibLibrary: fromArtifact,
            optLevel: try #require(OptimizationLevel(rawValue: optimization)),
            expectedStderr: ""
        )
    }
}
