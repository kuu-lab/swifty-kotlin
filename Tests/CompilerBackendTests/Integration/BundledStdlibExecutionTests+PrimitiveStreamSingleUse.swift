@testable import CompilerCore
import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [false, true], [0, 2])
    func primitiveStreamsAreSingleUse(fromArtifact: Bool, optimization: Int) throws {
        let source = try diffCaseSource("primitive_long_double_stream_single_use.kt", file: #filePath)
        try compileAndRunKotlin(
            source,
            expectedOutput: "long-before=0\nlong-parent=rejected\nlong-first=2\nlong-calls=2\nlong-child=rejected\ndouble-parent=rejected\nboxed-count=2\nboxed-reuse=rejected\nlong-sum=3\nlong-reuse=rejected\ndouble-before=0\ndouble-first=1.0\ndouble-calls=1\ndouble-reuse=rejected\nempty-present=false\nempty-reuse=rejected\nlong-limit=rejected\nlong-after-limit=4\ndouble-skip=rejected\ndouble-after-skip=4.5\n",
            moduleName: "PrimitiveStreamSingleUse",
            allowDefaultStdlibLibrary: fromArtifact,
            optLevel: try #require(OptimizationLevel(rawValue: optimization)),
            expectedStderr: ""
        )
    }
}
