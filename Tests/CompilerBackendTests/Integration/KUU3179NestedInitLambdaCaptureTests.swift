@testable import CompilerCore
import TestStdlibCache
import Testing

@Suite(.serialized)
struct KUU3179NestedInitLambdaCaptureTests {
    @Test(arguments: [0, 2])
    func nestedObjectInitBlockForwardsEnclosingCaptures(optimization: Int) throws {
        TestStdlibCache.shared.prepare()
        try compileAndRunKotlin(
            diffCaseSource("kuu_3179_nested_init_run_object_init_lambda_capture.kt", file: #filePath),
            expectedOutput: "OK\n",
            moduleName: "KUU3179NestedInitLambdaCapture",
            allowDefaultStdlibLibrary: true,
            optLevel: try #require(OptimizationLevel(rawValue: optimization)),
            expectedStderr: "",
            requireNoCompilerDiagnostics: true
        )
    }
}
