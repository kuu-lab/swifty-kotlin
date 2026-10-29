@testable import CompilerCore
@testable import CompilerTestSupport
import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [false, true], [0, 2])
    func coroutineNameRetainsItsContextType(fromArtifact: Bool, optimization: Int) throws {
        try compileAndRunKotlin(
            try diffCaseSource("coroutine_name_erased_type.kt", file: #filePath),
            expectedOutput: "true\ntrue\ntrue\nfalse\nfirst\nfirst\nnull\nfirst\ntrue\n",
            moduleName: "CoroutineNameType",
            allowDefaultStdlibLibrary: fromArtifact,
            optLevel: try #require(OptimizationLevel(rawValue: optimization)),
            expectedStderr: ""
        )
    }
}
