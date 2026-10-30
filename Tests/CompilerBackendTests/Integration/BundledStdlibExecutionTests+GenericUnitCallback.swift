@testable import CompilerCore
@testable import CompilerTestSupport
import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [false, true], [0, 2])
    func genericUnitCallbackReturnsUnit(fromArtifact: Bool, optimization: Int) throws {
        let source = try diffCaseSource("generic_callback_unit_coercion.kt", file: #filePath)
        try compileAndRunKotlin(
            source,
            expectedOutput: "count=1\nvalue=42\ntrue\nwrong type\n",
            moduleName: "GenericUnitCallback",
            allowDefaultStdlibLibrary: fromArtifact,
            optLevel: try #require(OptimizationLevel(rawValue: optimization)),
            expectedStderr: ""
        )
    }
}
