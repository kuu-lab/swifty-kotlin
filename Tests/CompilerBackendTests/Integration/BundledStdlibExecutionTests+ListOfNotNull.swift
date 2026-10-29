@testable import CompilerCore
@testable import CompilerTestSupport
import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [false, true], [0, 2])
    func listOfNotNullFiltersValuesWithBundledStdlib(fromArtifact: Bool, optimization: Int) throws {
        try compileAndRunKotlin(
            try diffCaseSource("list_of_not_null.kt", file: #filePath),
            expectedOutput: "[1, 2, 3]\n[]\n[a, b]\n[]\n[9]\n[]\n",
            moduleName: "ListOfNotNullBundledStdlib",
            allowDefaultStdlibLibrary: fromArtifact,
            optLevel: try #require(OptimizationLevel(rawValue: optimization)),
            expectedStderr: ""
        )
    }
}
