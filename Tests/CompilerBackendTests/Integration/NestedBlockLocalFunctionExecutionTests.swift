@testable import CompilerCore
import TestStdlibCache
import Testing

@Suite(.serialized)
struct NestedBlockLocalFunctionExecutionTests {
    @Test(arguments: [false, true], [0, 2])
    func upstreamAndNestedBlockCasesExecute(useArtifact: Bool, optimization: Int) throws {
        if useArtifact { TestStdlibCache.shared.prepare() }
        try compileAndRunKotlin(
            diffCaseSource("kuu_2247_nested_block_local_functions.kt", file: #filePath),
            expectedOutput: "OK\nOK\nOK\nwhile\nfor\nlambda\ninnerouter\n",
            moduleName: "KUU2247NestedBlockLocalFunctions",
            allowDefaultStdlibLibrary: useArtifact,
            optLevel: try #require(OptimizationLevel(rawValue: optimization)),
            expectedStderr: "",
            requireNoCompilerDiagnostics: true
        )
    }
}
