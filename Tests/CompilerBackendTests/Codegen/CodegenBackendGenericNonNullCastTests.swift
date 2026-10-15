@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Testing

@Suite
struct CodegenBackendGenericNonNullCastTests {
    /// KUU-2387: null assertions must survive generic erasure and remain catchable.
    @Test(arguments: [false, true], [0, 2])
    func nullAndValueCasts(useArtifact: Bool, optimizationLevel: Int) throws {
        let source = try diffCaseSource("generic_nonnull_cast.kt", file: #filePath)
        let expected = "NPE\n" + String(repeating: "true\n", count: 5)
            + "NPE\ntrue\nNPE\n" + String(repeating: "true\n", count: 4)
            + "NPE\n" + String(repeating: "OK\n", count: 13)
        try assertKotlinOutput(
            source,
            moduleName: "GenericNonNullCast",
            expected: expected,
            optLevel: try #require(OptimizationLevel(rawValue: optimizationLevel)),
            allowDefaultStdlibLibrary: useArtifact
        )
    }
}
