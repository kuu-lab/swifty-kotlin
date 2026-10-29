@testable import CompilerCore
import Testing

@Suite(.serialized)
struct SamCallableReferenceTypeTests {
    @Test(arguments: [false, true], [0, 2])
    func samTypesFollowTheirInterfaces(fromArtifact: Bool, optimization: Int) throws {
        try compileAndRunKotlin(
            try diffCaseSource("sam_callable_ref_function_type.kt", file: #filePath),
            expectedOutput: "false\ntrue\nfalse\ntrue\nfalse\ntrue\nfalse\ntrue\ntrue\ntrue\ntrue\ntrue\nfalse\nfalse\nfalse\ntrue\ntrue\ntrue\ntrue\n",
            moduleName: "SamCallableReferenceFunctionType",
            allowDefaultStdlibLibrary: fromArtifact,
            optLevel: try #require(OptimizationLevel(rawValue: optimization)),
            expectedStderr: ""
        )
    }
}
