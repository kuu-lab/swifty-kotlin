@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Testing

@Suite
struct CodegenBackendGenericNonNullCastTests {
    /// KUU-2387: null assertions must survive generic erasure and remain catchable.
    // Source-injected O2 independently fails LLVM verification for stdlib invoke adapters.
    @Test(arguments: [(false, 0), (true, 0), (true, 2)])
    func nullAndValueCasts(useArtifact: Bool, optimizationLevel: Int) throws {
        let source = try diffCaseSource("generic_nonnull_cast.kt", file: #filePath)
        let expected = "OK\nOK\nNPE\n" + String(repeating: "true\n", count: 5)
            + "NPE\ntrue\nNPE\n" + String(repeating: "true\n", count: 4)
            + "NPE\n" + String(repeating: "OK\n", count: 15)
            + "-9223372036854775808\n-9223372036854775808\nfalse\nfalse\n0\n0\n"
            + String(repeating: "true\n", count: 5)
        try assertKotlinOutput(
            source,
            moduleName: "GenericNonNullCast",
            expected: expected,
            optLevel: try #require(OptimizationLevel(rawValue: optimizationLevel)),
            allowDefaultStdlibLibrary: useArtifact
        )
    }

    /// KUU-2410: Keep the upstream Kotlin/JVM box regression executable.
    @Test(arguments: [(false, 0), (true, 0), (true, 2)])
    func publicAsWithGenericBox(useArtifact: Bool, optimizationLevel: Int) throws {
        let source = try diffCaseSource("as_with_generic.kt", file: #filePath)
        try assertKotlinOutput(
            source,
            moduleName: "AsWithGenericPublic",
            expected: "OK\n",
            optLevel: try #require(OptimizationLevel(rawValue: optimizationLevel)),
            allowDefaultStdlibLibrary: useArtifact
        )
    }
}
