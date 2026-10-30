#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerTestSupport
import Foundation
import Testing

/// A `var` override must keep the overridden `var`'s exact type (the property
/// is read and written, so the type is invariant), while a `val` override may
/// narrow it (covariant read). Found via systematic kotlinc-parity probing:
/// kotlinc rejects `override var x: String` over `open var x: Any` ("type of
/// 'var x' doesn't match the type of the overridden 'var' property") but
/// kswiftc previously applied no property-type check at all.
@Suite
struct PropertyTypeOverrideTests {
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
    func rejectsVarNarrowingOverride() throws {
        let diagnostics = try diagnosticsFor("""
        open class A { open var x: Any = "" }
        class B : A() { override var x: String = "s" }
        """)
        assertHasDiagnostic("KSWIFTK-SEMA-OVERRIDE-TYPE", in: diagnostics)
    }

    @Test
    func rejectsVarWideningOverride() throws {
        let diagnostics = try diagnosticsFor("""
        open class A { open var x: String = "" }
        class B : A() { override var x: Any = "s" }
        """)
        assertHasDiagnostic("KSWIFTK-SEMA-OVERRIDE-TYPE", in: diagnostics)
    }

    @Test
    func rejectsValWideningOverride() throws {
        let diagnostics = try diagnosticsFor("""
        open class A { open val x: String = "" }
        class B : A() { override val x: Any = "s" }
        """)
        assertHasDiagnostic("KSWIFTK-SEMA-OVERRIDE-TYPE", in: diagnostics)
    }

    @Test
    func acceptsValNarrowingOverride() throws {
        let diagnostics = try diagnosticsFor("""
        open class A { open val x: Any = "" }
        class B : A() { override val x: String = "s" }
        """)
        assertNoDiagnostic("KSWIFTK-SEMA-OVERRIDE-TYPE", in: diagnostics)
    }

    @Test
    func acceptsVarOverValWithSubtype() throws {
        let diagnostics = try diagnosticsFor("""
        open class A { open val x: Any = "" }
        class B : A() { override var x: String = "s" }
        """)
        assertNoDiagnostic("KSWIFTK-SEMA-OVERRIDE-TYPE", in: diagnostics)
    }

    @Test
    func acceptsInferredValOverride() throws {
        let diagnostics = try diagnosticsFor("""
        interface Named { val name: String }
        class C(override val name = "c") : Named
        """)
        #expect(!diagnostics.contains { $0.code == "KSWIFTK-SEMA-OVERRIDE-TYPE" })
    }

    @Test
    func acceptsVarOverrideSameType() throws {
        let diagnostics = try diagnosticsFor("""
        open class A { open var x: Any = "" }
        class B : A() { override var x: Any = "s" }
        """)
        assertNoDiagnostic("KSWIFTK-SEMA-OVERRIDE-TYPE", in: diagnostics)
    }

    /// Overrides whose type comes from an initializer carry a placeholder type
    /// while the open/final/override pass runs, so the same checks have to be
    /// re-applied once body inference publishes the real property type.
    /// kotlinc rejects `override var x = "s"` over `open var x: Any` with
    /// "type of 'var x: String' doesn't match the type of the overridden
    /// 'var' property 'var x: Any'".

    @Test
    func rejectsInferredVarNarrowingOverride() throws {
        let diagnostics = try diagnosticsFor("""
        open class A { open var x: Any = "" }
        class B : A() { override var x = "s" }
        """)
        assertHasDiagnostic("KSWIFTK-SEMA-OVERRIDE-TYPE", in: diagnostics)
    }

    @Test
    func rejectsInferredVarWideningOverride() throws {
        let diagnostics = try diagnosticsFor("""
        open class A { open var x: String = "" }
        class B : A() { override var x = "s" as Any }
        """)
        assertHasDiagnostic("KSWIFTK-SEMA-OVERRIDE-TYPE", in: diagnostics)
    }

    @Test
    func rejectsInferredValWideningOverride() throws {
        let diagnostics = try diagnosticsFor("""
        open class A { open val x: String = "" }
        class B : A() { override val x = "s" as Any }
        """)
        assertHasDiagnostic("KSWIFTK-SEMA-OVERRIDE-TYPE", in: diagnostics)
    }

    @Test
    func acceptsInferredValNarrowingOverride() throws {
        let diagnostics = try diagnosticsFor("""
        open class A { open val x: Any = "" }
        class B : A() { override val x = "s" }
        """)
        assertNoDiagnostic("KSWIFTK-SEMA-OVERRIDE-TYPE", in: diagnostics)
    }

    @Test
    func acceptsInferredVarOverrideSameType() throws {
        let diagnostics = try diagnosticsFor("""
        open class A { open var x: String = "" }
        class B : A() { override var x = "s" }
        """)
        assertNoDiagnostic("KSWIFTK-SEMA-OVERRIDE-TYPE", in: diagnostics)
    }

    @Test
    func acceptsInferredVarOverValNarrowing() throws {
        let diagnostics = try diagnosticsFor("""
        open class A { open val x: Any = "" }
        class B : A() { override var x = "s" }
        """)
        assertNoDiagnostic("KSWIFTK-SEMA-OVERRIDE-TYPE", in: diagnostics)
    }

    @Test
    func rejectsInferredOverrideWhenParentDeclaredFirstAndChildAfter() throws {
        // The parent's explicit type must be found regardless of the order in
        // which property bodies were type-checked.
        let diagnostics = try diagnosticsFor("""
        class B : A() { override var x = "s" }
        open class A { open var x: Any = "" }
        """)
        assertHasDiagnostic("KSWIFTK-SEMA-OVERRIDE-TYPE", in: diagnostics)
    }

    @Test
    func rejectsInferredVarOverrideInsideObjectLiteral() throws {
        let diagnostics = try diagnosticsFor("""
        open class A { open var x: Any = "" }
        val o = object : A() { override var x = "s" }
        """)
        assertHasDiagnostic("KSWIFTK-SEMA-OVERRIDE-TYPE", in: diagnostics)
    }

    @Test
    func rejectsInferredVarOverrideInsideLocalClass() throws {
        let diagnostics = try diagnosticsFor("""
        open class A { open var x: Any = "" }
        fun f() { class L : A() { override var x = "s" } }
        """)
        assertHasDiagnostic("KSWIFTK-SEMA-OVERRIDE-TYPE", in: diagnostics)
    }

    @Test
    func rejectsInferredValOverrideInsideNestedObjectLiteral() throws {
        let diagnostics = try diagnosticsFor("""
        open class A { open val x: String = "" }
        val o = object { val inner = object : A() { override val x = "s" as Any } }
        """)
        assertHasDiagnostic("KSWIFTK-SEMA-OVERRIDE-TYPE", in: diagnostics)
    }

    @Test
    func acceptsInferredValOverrideInsideObjectLiteral() throws {
        let diagnostics = try diagnosticsFor("""
        open class A { open val x: Any = "" }
        val o = object : A() { override val x = "s" }
        """)
        assertNoDiagnostic("KSWIFTK-SEMA-OVERRIDE-TYPE", in: diagnostics)
    }

    @Test
    func acceptsInferredVarOverrideInsideLocalClass() throws {
        let diagnostics = try diagnosticsFor("""
        open class A { open var x: String = "" }
        fun f() { class L : A() { override var x = "t" } }
        """)
        assertNoDiagnostic("KSWIFTK-SEMA-OVERRIDE-TYPE", in: diagnostics)
    }
}
#endif
