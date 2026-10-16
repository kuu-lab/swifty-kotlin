#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Testing

@Suite
struct CodegenBackendLocalClassInheritedCaptureTests {
    @Test(arguments: [true, false])
    func inheritedCaptureFieldsAreInitialized(allowDefaultStdlibLibrary: Bool) throws {
        let source = try diffCaseSource("local_class_inherited_capture.kt", file: #filePath)
        if allowDefaultStdlibLibrary { _ = try testStdlibArtifactPath() }
        for optLevel in [OptimizationLevel.O0, .O2] {
            try assertKotlinOutput(
                source,
                moduleName: "KUU2272LocalClassInheritedCapture",
                expected: "OK\nOK\nOK\nOK\nbase|derived\nOK\n",
                optLevel: optLevel,
                allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
            )
        }
    }
}
#endif
