@testable import CompilerCore
@testable import CompilerTestSupport
import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [false, true], [0, 2])
    func linkedListStringUsesPublicCollectionIdentity(fromArtifact: Bool, optimization: Int) throws {
        let source = try diffCaseSource("java_linkedlist_self_string.kt", file: #filePath)
        try compileAndRunKotlin(
            source,
            expectedOutput: "[]\n[null, tail, (this Collection)]\n[null, tail, (this Collection)]\n[null, tail, (this Collection)]\n[[value], other, (this Collection)]\n",
            moduleName: "LinkedListSelfString",
            allowDefaultStdlibLibrary: fromArtifact,
            optLevel: try #require(OptimizationLevel(rawValue: optimization)),
            expectedStderr: ""
        )
    }
}
