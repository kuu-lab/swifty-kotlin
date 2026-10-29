@testable import CompilerCore
@testable import CompilerTestSupport
import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [false, true], [0, 2])
    func mathExternalBridgeKeepsPrimitiveArguments(fromArtifact: Bool, optimization: Int) throws {
        try compileAndRunKotlin(
            try diffCaseSource("java_lang_math_external_bridge.kt", file: #filePath),
            expectedOutput: String(repeating: "true\n", count: 9),
            moduleName: "MathExternalBridgeABI",
            allowDefaultStdlibLibrary: fromArtifact,
            optLevel: try #require(OptimizationLevel(rawValue: optimization)),
            expectedStderr: ""
        )
    }
}
