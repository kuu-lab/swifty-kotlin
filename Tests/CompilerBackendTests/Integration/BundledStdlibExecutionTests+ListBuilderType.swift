@testable import CompilerCore
@testable import CompilerTestSupport
import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [false, true], [0, 2])
    func listBuilderKeepsMutableTypeAndFreezes(fromArtifact: Bool, optimization: Int) throws {
        let source = try diffCaseSource("list_builder_erased_receiver.kt", file: #filePath)
        try compileAndRunKotlin(
            source,
            expectedOutput: "[1, 2]\ntrue\nfalse\ntrue\nfrozen\n[1, 2]\n",
            moduleName: "ListBuilderErasedReceiver",
            allowDefaultStdlibLibrary: fromArtifact,
            optLevel: try #require(OptimizationLevel(rawValue: optimization)),
            expectedStderr: ""
        )
    }
}
