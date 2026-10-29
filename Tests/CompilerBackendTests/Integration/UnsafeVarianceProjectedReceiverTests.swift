@testable import CompilerCore
import Foundation
import Testing

@Suite
struct UnsafeVarianceProjectedReceiverTests {
    @Test(arguments: [false, true], [0, 2])
    func testReferenceCaseRunsForSourceAndLibraryStdlib(
        useStdlibLibrary: Bool,
        optimization: Int
    ) throws {
        try compileAndRunKotlin(
            try diffCaseSource("unsafe_variance_projected_receiver.kt", file: #filePath),
            expectedOutput: "OK",
            moduleName: "UnsafeVarianceProjectedReceiver",
            allowDefaultStdlibLibrary: useStdlibLibrary,
            optLevel: try #require(OptimizationLevel(rawValue: optimization)),
            expectedStderr: ""
        )
    }
}
