@testable import CompilerCore
import TestStdlibCache
import Testing

@Suite(.serialized)
struct LocalFunctionLocalClassChainTests {
    @Test(arguments: [0, 2])
    func localFunctionForwardsLocalClassCaptures(optimization: Int) throws {
        TestStdlibCache.shared.prepare()
        try compileAndRunKotlin(
            diffCaseSource("kuu_2931_local_function_local_class_chain.kt", file: #filePath),
            expectedOutput: "OK\n",
            moduleName: "KUU2931LocalFunctionLocalClassChain",
            allowDefaultStdlibLibrary: true,
            optLevel: try #require(OptimizationLevel(rawValue: optimization)),
            expectedStderr: "",
            requireNoCompilerDiagnostics: true
        )
    }
}
