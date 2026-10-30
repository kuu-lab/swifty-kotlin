@testable import CompilerCore
import TestStdlibCache
import Testing

@Suite(.serialized)
struct KUU3590NestedInitOuterMemberCallTests {
    @Test(arguments: [0, 2])
    func outerMemberCallFromObjectInitInsideRunPreservesEnclosingReceiver(optimization: Int) throws {
        TestStdlibCache.shared.prepare()
        try compileAndRunKotlin(
            diffCaseSource("kuu_3590_outer_member_call_nested_object_init.kt", file: #filePath),
            expectedOutput: "OK\n",
            moduleName: "KUU3590NestedInitOuterMemberCall",
            allowDefaultStdlibLibrary: true,
            optLevel: try #require(OptimizationLevel(rawValue: optimization)),
            expectedStderr: "",
            requireNoCompilerDiagnostics: true
        )
    }
}
