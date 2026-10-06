#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Testing

@Suite
struct CodegenBackendSequenceWindowedTransformTests {
    @Test(arguments: [true, false])
    func transformsRetainTheirEnvironment(allowDefaultStdlibLibrary: Bool) throws {
        let source = try diffCaseSource("sequence_windowed_transform_capture.kt")
        try assertKotlinOutput(
            source,
            moduleName: "SequenceWindowedTransformCapture",
            expected: """
                [2, 2]
                [2, 2]
                [2, 2, 1]
                [3, 9]
                [12, 12]
                [window:2, window:2]
                []
                [[1, 2], [2, 3]]
                """ + "\n",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }
}
#endif
