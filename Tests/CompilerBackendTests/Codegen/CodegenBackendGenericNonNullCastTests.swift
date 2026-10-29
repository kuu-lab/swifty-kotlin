@testable import CompilerCore
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

    /// KUU-3344: Explicit `T & Any` returns must preserve generic values and throw a catchable NPE for null.
    @Test
    func definitelyNonNullIntersectionCast() throws {
        let source = try diffCaseSource("definitely_nonnull_type_parameter_cast.kt", file: #filePath)
        try assertKotlinOutput(
            source,
            moduleName: "DefinitelyNonNullTypeParameterCast",
            expected: "42\nOK\nNPE\nOK\nevaluations:1\nNPE\nevaluations:1\n"
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
