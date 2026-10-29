@testable import CompilerCore
@testable import CompilerTestSupport
import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [false, true], [0, 2])
    func flowHandlesRetainTheirNominalType(fromArtifact: Bool, optimization: Int) throws {
        let source = try diffCaseSource("flow_erased_nominal_type.kt", file: #filePath)
        try compileAndRunKotlin(
            source,
            expectedOutput: "true\ntrue\nfalse\nwrong type\n",
            moduleName: "FlowErasedNominalType",
            allowDefaultStdlibLibrary: fromArtifact,
            optLevel: try #require(OptimizationLevel(rawValue: optimization)),
            expectedStderr: ""
        )
    }
}
