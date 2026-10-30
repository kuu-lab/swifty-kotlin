@testable import CompilerCore
import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [false, true], [0, 2])
    func charSequenceStreamsRemainLazy(fromArtifact: Bool, optimization: Int) throws {
        let source = try diffCaseSource("charsequence_streams_lazy.kt", file: #filePath)
        try compileAndRunKotlin(
            source,
            expectedOutput: "chars=65,55357,56832,66\npoints=65,128512,66\nempty=\nunpaired=88,55296,89,56320\nlate-map=133\nlate-boxed=2\nlate-custom=131\ncalls-before=0\nfirst=65\ncalls-after=1\nlate-long=133\nonce=1\nreuse=rejected\n",
            moduleName: "CharSequenceStreams",
            allowDefaultStdlibLibrary: fromArtifact,
            optLevel: try #require(OptimizationLevel(rawValue: optimization)),
            expectedStderr: ""
        )
    }
}
