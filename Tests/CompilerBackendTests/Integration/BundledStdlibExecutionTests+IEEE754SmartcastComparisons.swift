@testable import CompilerCore
import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [0, 2])
    func testAnySmartcastFloatingComparisonsUseIEEEOperators(optimization: Int) throws {
        try compileAndRunKotlin(
            try diffCaseSource("kuu_2899_any_smartcast_ieee_comparisons.kt", file: #filePath),
            expectedOutput: try diffCaseSource("kuu_2899_any_smartcast_ieee_comparisons.expected", file: #filePath),
            moduleName: "KUU2899IEEE754SmartcastComparisons",
            allowDefaultStdlibLibrary: true,
            optLevel: try #require(OptimizationLevel(rawValue: optimization)),
            expectedStderr: "",
            requireNoCompilerDiagnostics: true
        )
    }
}
