@testable import CompilerCore
@testable import CompilerTestSupport
import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [false, true], [0, 2])
    func reifiedClassLiteralUsesLambdaCapture(fromArtifact: Bool, optimization: Int) throws {
        let source = try diffCaseSource("reified_class_literal_captured_lambda.kt", file: #filePath)
        try compileAndRunKotlin(
            source,
            expectedOutput: "direct:OK2\nplain:OK2\ncross:OK2\ncross-literal:OK2\ncross-const:OK\ncaptured:hello\ncross-check-yes:yes\ncross-check-no:no\n",
            moduleName: "ReifiedClassLiteralLambda",
            allowDefaultStdlibLibrary: fromArtifact,
            optLevel: try #require(OptimizationLevel(rawValue: optimization)),
            expectedStderr: ""
        )
    }

    @Test(arguments: [false, true], [0, 2])
    func reifiedClassLiteralSurvivesSuspendInlineChain(fromArtifact: Bool, optimization: Int) throws {
        let source = try diffCaseSource("suspend_inline_crossinline_reified_class_literal.kt", file: #filePath)
        try compileAndRunKotlin(
            source,
            expectedOutput: "OK2\nOK2\nOK2\n",
            moduleName: "ReifiedClassLiteralSuspend",
            allowDefaultStdlibLibrary: fromArtifact,
            optLevel: try #require(OptimizationLevel(rawValue: optimization)),
            expectedStderr: ""
        )
    }
}
