@testable import CompilerCore
import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [false, true], [0, 2])
    func callableReferenceArgumentsCrossBoxedReceiverBoundary(fromSource: Bool, optimization: Int) throws {
        let level = try #require(OptimizationLevel(rawValue: optimization))
        try compileAndRunKotlin(
            try diffCaseSource("callable_reference_argument_boxing.kt", file: #filePath),
            expectedOutput: "true\nfalse\nA\n1.5\n2.5\ntrue\ntrue\nnull\n-0.0\n-0.0\n-0.0\n-0.0\n",
            moduleName: "CallableReferenceArgumentBoxing",
            allowDefaultStdlibLibrary: !fromSource,
            optLevel: level
        )
    }
}
