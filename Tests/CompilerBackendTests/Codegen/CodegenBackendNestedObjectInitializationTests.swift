#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Testing

@Suite
struct CodegenBackendNestedObjectInitializationTests {
    @Test(arguments: [true, false])
    func testNestedObjectWithoutSupertypesInitializesProperties(allowDefaultStdlibLibrary: Bool) throws {
        if allowDefaultStdlibLibrary { _ = try testStdlibArtifactPath() }
        for optLevel in [OptimizationLevel.O0, .O2] {
            try assertKotlinOutput(
                try diffCaseSource("nested_object_without_supertypes.kt"),
                moduleName: "KUU2042NestedObjectProperties",
                expected: "5\n",
                optLevel: optLevel,
                allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
            )
        }
    }

    @Test(arguments: [true, false])
    func testNestedObjectWithoutSupertypesInitializesLazilyOnce(allowDefaultStdlibLibrary: Bool) throws {
        if allowDefaultStdlibLibrary { _ = try testStdlibArtifactPath() }
        for optLevel in [OptimizationLevel.O0, .O2] {
            try assertKotlinOutput(
                try diffCaseSource("nested_object_without_supertypes_lazy_init.kt"),
                moduleName: "KUU2042NestedObjectLazyInitialization",
                expected: "11\nbefore non-const\nM init\nready:5:3\nready:5:4\ntrue\nN init\n7\nOuter init\n7\nDeep init\n9\n9\nValues init\n12\n11\n12\n",
                optLevel: optLevel,
                allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
            )
        }
    }
}
#endif
