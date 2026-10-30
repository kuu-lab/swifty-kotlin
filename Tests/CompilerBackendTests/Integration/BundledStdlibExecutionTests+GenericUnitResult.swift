@testable import CompilerCore
import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [false, true], [0, 2])
    func genericUnitResultIsCoercedWithoutCasting(fromArtifact: Bool, optimization: Int) throws {
        let source = try diffCaseSource("generic_unit_result_coercion.kt", file: #filePath)
        try compileAndRunKotlin(
            source,
            expectedOutput: "before=false\ncompletion=ok\nresult=kotlin.Unit done=true\nused=kotlin.Unit\ndiscarded=ok\nstring=cast\nexplicit=cast\n",
            moduleName: "GenericUnitResultCoercion",
            allowDefaultStdlibLibrary: fromArtifact,
            optLevel: try #require(OptimizationLevel(rawValue: optimization)),
            expectedStderr: ""
        )
    }
}
