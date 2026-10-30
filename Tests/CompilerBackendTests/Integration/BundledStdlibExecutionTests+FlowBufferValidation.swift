@testable import CompilerCore
import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [false, true], [0, 2])
    func flowBufferResolvesDefaultsAndValidation(fromArtifact: Bool, optimization: Int) throws {
        let source = try diffCaseSource("flow_buffer_capacity_validation.kt", file: #filePath)
        try compileAndRunKotlin(
            source,
            expectedOutput: "default=[1, 2]\nzero=[1, 2]\ntwo=[1, 2]\nbuffered=[1, 2]\nconflated=accepted\ndrop-latest=accepted\ndefault-overflow=accepted\nnegative=rejected\nnegative-overflow=rejected\nconflated-overflow=rejected\nowner=-3\nuser-flow=-3\n",
            moduleName: "FlowBufferCapacityValidation",
            allowDefaultStdlibLibrary: fromArtifact,
            optLevel: try #require(OptimizationLevel(rawValue: optimization)),
            expectedStderr: ""
        )
    }
}
