#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerTestSupport
import Foundation
import Testing

/// kotlinc rejects named object declarations in every local position with
/// "named object 'X' cannot be local. Try to use an anonymous object
/// instead." (and "modifier 'companion' is not applicable inside …" for
/// companion objects). kswiftc accepted all of them — and in the anonymous
/// object literal case the `companion object` member failed every member
/// parse, silently dropping the literal's whole declaration.
@Suite
struct LocalNamedObjectPositionTests {
    private func diagnosticsFor(_ source: String) throws -> [Diagnostic] {
        let inputPath = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".kt").path
        let ctx = makeCompilationContext(
            inputs: [inputPath],
            includeStdlib: false,
            allowDefaultStdlibLibrary: false
        )
        _ = ctx.sourceManager.addFile(path: inputPath, contents: Data(source.utf8))
        try runSema(ctx)
        return ctx.diagnostics.diagnostics
    }

    @Test
    func rejectsObjectInFunctionBody() throws {
        let diagnostics = try diagnosticsFor("""
        fun f() { object O {} }
        """)
        assertHasDiagnostic("KSWIFTK-SEMA-0429", in: diagnostics)
    }

    @Test
    func rejectsObjectMemberOfLocalClass() throws {
        let diagnostics = try diagnosticsFor("""
        fun f() { class L { object O {} } }
        """)
        assertHasDiagnostic("KSWIFTK-SEMA-0429", in: diagnostics)
    }

    @Test
    func rejectsObjectMemberOfLocalObject() throws {
        let diagnostics = try diagnosticsFor("""
        fun f() { object O { object P {} } }
        """)
        let locals = diagnostics.filter {
            $0.severity == .error && $0.code == "KSWIFTK-SEMA-0429"
        }
        #expect(locals.count == 2, "Got: \(diagnostics)")
    }

    @Test
    func rejectsObjectMemberOfAnonymousObject() throws {
        let diagnostics = try diagnosticsFor("""
        val x = object { object N {} }
        """)
        assertHasDiagnostic("KSWIFTK-SEMA-0429", in: diagnostics)
    }

    @Test
    func rejectsObjectInsideEnumEntry() throws {
        let diagnostics = try diagnosticsFor("""
        enum class En { E1 { object O {} }, E2 }
        """)
        assertHasDiagnostic("KSWIFTK-SEMA-0429", in: diagnostics)
    }

    @Test
    func rejectsCompanionInsideAnonymousObject() throws {
        let diagnostics = try diagnosticsFor("""
        val y = object { companion object {} }
        """)
        assertHasDiagnostic("KSWIFTK-SEMA-0401", in: diagnostics)
    }

    @Test
    func rejectsCompanionInsideEnumEntry() throws {
        let diagnostics = try diagnosticsFor("""
        enum class En { E1 { companion object {} }, E2 }
        """)
        assertHasDiagnostic("KSWIFTK-SEMA-0401", in: diagnostics)
    }

    @Test
    func rejectsObjectInObjectMemberFunction() throws {
        let diagnostics = try diagnosticsFor("""
        object Outer { fun m() { object O {} } }
        """)
        assertHasDiagnostic("KSWIFTK-SEMA-0429", in: diagnostics)
    }

    @Test
    func acceptsTopLevelAndMemberObjects() throws {
        let diagnostics = try diagnosticsFor("""
        class Top { object M {} }
        object Outer { object Inner {} }
        enum class En { E1 { val x = 1 }, E2 }
        """)
        assertNoDiagnostic("KSWIFTK-SEMA-0429", in: diagnostics)
    }
}
#endif
