@testable import CompilerCore
import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [false, true], [0, 2])
    func storedPrimitiveLambdasCheckErasedArguments(fromArtifact: Bool, optimization: Int) throws {
        let source = try diffCaseSource("stored_primitive_lambda_checkcast.kt", file: #filePath)
        try compileAndRunKotlin(
            source,
            expectedOutput: "TF\nflag cast\n5\nnumber cast\n8\nnull,4\n3.5\n",
            moduleName: "StoredPrimitiveLambdaCheckcast",
            allowDefaultStdlibLibrary: fromArtifact,
            optLevel: try #require(OptimizationLevel(rawValue: optimization)),
            expectedStderr: ""
        )
    }
}
