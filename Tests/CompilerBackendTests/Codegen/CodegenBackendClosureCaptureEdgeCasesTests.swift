@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

@Suite
struct CodegenBackendClosureCaptureEdgeCasesTests {
    @Test
    func boundReferenceInSuperConstructorCapturesOuterProperty() throws {
        try assertKotlinOutput(
            diffCase("kuu_3183_super_ctor_bound_reference.kt"),
            moduleName: "KUU3183SuperConstructorBoundReference",
            expected: "OK\n"
        )
    }

    @Test
    func capturedVarSurvivesLetAndFinally() throws {
        try assertKotlinOutput(
            diffCase("kuu_3183_captured_var_finally.kt"),
            moduleName: "KUU3183CapturedVarFinally",
            expected: "OK\n"
        )
    }

    @Test
    func extensionSetInAnonymousObjectInitializerUsesCapture() throws {
        try assertKotlinOutput(
            diffCase("kuu_3183_object_init_extension_set.kt"),
            moduleName: "KUU3183ObjectInitExtensionSet",
            expected: "OK\n"
        )
    }

    private func diffCase(_ name: String) throws -> String {
        let repository = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        return try String(
            contentsOf: repository.appendingPathComponent("Scripts/diff_cases/\(name)"),
            encoding: .utf8
        )
    }
}
