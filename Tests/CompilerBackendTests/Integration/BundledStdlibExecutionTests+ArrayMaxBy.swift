@testable import CompilerCore
import Testing

extension BundledStdlibExecutionTests {
    // KUU-2045: pin the xenocom selector call and Kotlin's maxBy contracts in
    // both stdlib modes, including projected receivers and non-local returns.
    @Test(arguments: [false, true], [0, 2])
    func testArrayMaxBySourceAndArtifact(
        useStdlibLibrary: Bool,
        optimization: Int
    ) throws {
        try compileAndRunKotlin(
            try diffCaseSource("array_max_by.kt", file: #filePath),
            expectedOutput: try diffCaseSource("array_max_by.expected", file: #filePath),
            moduleName: "KUU2045ArrayMaxBy",
            allowDefaultStdlibLibrary: useStdlibLibrary,
            optLevel: try #require(OptimizationLevel(rawValue: optimization)),
            expectedStderr: ""
        )
    }
}
