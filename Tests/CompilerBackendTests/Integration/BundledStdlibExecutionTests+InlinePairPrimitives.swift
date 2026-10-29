@testable import CompilerCore
@testable import CompilerTestSupport
import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [false, true], [0, 2])
    func inlineAssociateBoxesPrimitivePairComponents(fromArtifact: Bool, optimization: Int) throws {
        let source = try diffCaseSource("primitive_pair_in_inline_associate.kt", file: #filePath)
        try compileAndRunKotlin(
            source,
            expectedOutput: "(a, b)\n(true, false)\n(1.0, 2.0)\n(1.0, 2.0)\n{a=1, b=1}\n{a=a}\n{true=true}\n{1.0=1.0}\n[(null, 1), (-0.0, 1), (1.5, 1)]\n[(null, 1), (a, 1)]\n{7=7}\ntrue\n{9=9}\ntrue\n",
            moduleName: "InlinePairPrimitives",
            allowDefaultStdlibLibrary: fromArtifact,
            optLevel: try #require(OptimizationLevel(rawValue: optimization)),
            expectedStderr: ""
        )
    }
}
