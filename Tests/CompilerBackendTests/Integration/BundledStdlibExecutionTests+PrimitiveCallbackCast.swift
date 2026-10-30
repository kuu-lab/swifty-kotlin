@testable import CompilerCore
@testable import CompilerTestSupport
import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [false, true], [0, 2])
    func primitiveCallbackCheckcastUnboxesArguments(fromArtifact: Bool, optimization: Int) throws {
        let source = try diffCaseSource("primitive_callback_after_cast.kt", file: #filePath)
        try compileAndRunKotlin(
            source,
            expectedOutput: "T,F\n098f\n-1,2\n2,3\n1.5,-0.0\nnull,-1,1\n098f6bcd4621d373cade4e832627b4f6\nwrong type\n",
            moduleName: "PrimitiveCallbackAfterCast",
            allowDefaultStdlibLibrary: fromArtifact,
            optLevel: try #require(OptimizationLevel(rawValue: optimization)),
            expectedStderr: ""
        )
    }
}
