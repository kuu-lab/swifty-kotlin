@testable import CompilerCore
import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [false, true], [0, 2])
    func sinkOutputCallbacksReceiveByteArrays(fromArtifact: Bool, optimization: Int) throws {
        let source = try diffCaseSource("kotlinx_io_sink_bytearray_identity.kt", file: #filePath)
        try compileAndRunKotlin(
            source,
            expectedOutput: "3\n-1\n20\n30\n65\nclosed\n",
            moduleName: "SinkByteArrayIdentity",
            allowDefaultStdlibLibrary: fromArtifact,
            optLevel: try #require(OptimizationLevel(rawValue: optimization)),
            expectedStderr: ""
        )
    }
}
