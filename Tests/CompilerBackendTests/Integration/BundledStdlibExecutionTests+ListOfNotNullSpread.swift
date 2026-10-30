@testable import CompilerCore
import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [false, true], [0, 2])
    func listOfNotNullSpreadSelectsVararg(fromArtifact: Bool, optimization: Int) throws {
        try compileAndRunKotlin(
            try diffCaseSource("list_of_not_null_spread.kt", file: #filePath),
            expectedOutput: "[4, 5]\n[1, 4, 5, 8]\n[]\n[9]\n1\n3\n",
            moduleName: "ListOfNotNullSpread",
            allowDefaultStdlibLibrary: fromArtifact,
            optLevel: try #require(OptimizationLevel(rawValue: optimization)),
            expectedStderr: ""
        )
    }
}
