#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct CodegenBackendSequenceChunkedWindowedTransformRegressionTests {

    @Test
    func testCodegenSequenceChunkedWindowedTransformRegression() throws {
        let source = try diffCaseSource("sequence_chunked_windowed_transform.kt")

        try assertKotlinOutput(
            source,
            moduleName: "SequenceChunkedWindowedTransformRegression",
            expected:
                """
                [3, 7, 5]
                [6, 9, 12]
                [6, 9, 12]
                [3, 7]
                [103, 107, 105]
                [106, 109, 112]
                [106, 109, 112]
                []
                []
                chunked(0) transform: size 0 must be greater than zero.
                windowed(0) transform: Both size 0 and step 1 must be greater than zero.
                """
                + "\n"
        )
    }
}
#endif
