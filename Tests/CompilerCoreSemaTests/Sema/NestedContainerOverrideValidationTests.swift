#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerTestSupport
import Foundation
import Testing

/// Members of named nested objects, companion objects, and enum-entry bodies
/// were skipped by the open/final/override walk: `extractDeclInfo` only
/// recursed into nested classes, `validateMissingOverride` only emitted
/// class-style hiding diagnostics for `.class` owners, and enum-entry
/// members never reached `validateMemberOverrides`. kotlinc rejects every
/// case below; kswiftc previously accepted them all (KUU-4161).
///
/// Known remaining gaps shared with top-level classes (tracked separately,
/// not entry-specific): hiding a *concrete* interface member without
/// `override` produces no diagnostic for any owner kind, and
/// `override`-on-nothing inside enum bodies is suppressed by the synthetic
/// `kotlin.Enum` shell's incomplete member index (KUU-4170).
@Suite
struct NestedContainerOverrideValidationTests {
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

    // MARK: - Nested named objects

    @Test
    func rejectsMissingOverrideInNestedObject() throws {
        let diagnostics = try diagnosticsFor("""
        open class B { open fun f() = 0 }
        class C { object O : B() { fun f() = 1 } }
        """)
        assertHasDiagnostic("KSWIFTK-SEMA-OVERRIDE", in: diagnostics)
    }

    @Test
    func rejectsOverrideOfNonexistentMemberInNestedObject() throws {
        let diagnostics = try diagnosticsFor("""
        open class B { open fun f() = 0 }
        class C { object O : B() { override fun g() = 1 } }
        """)
        assertHasDiagnostic("KSWIFTK-SEMA-OVERRIDE-NOTHING", in: diagnostics)
    }

    @Test
    func rejectsValOverridingVarInNestedObject() throws {
        let diagnostics = try diagnosticsFor("""
        open class B { open var x: Any = 1 }
        class C { object O : B() { override val x: Any = 1 } }
        """)
        assertHasDiagnostic("KSWIFTK-SEMA-OVERRIDE-MUTABILITY", in: diagnostics)
    }

    @Test
    func rejectsMissingOverrideInObjectNestedInObject() throws {
        let diagnostics = try diagnosticsFor("""
        open class B { open fun f() = 0 }
        object Outer { object Inner : B() { fun f() = 1 } }
        """)
        assertHasDiagnostic("KSWIFTK-SEMA-OVERRIDE", in: diagnostics)
    }

    @Test
    func rejectsMissingOverrideInDeeplyNestedObject() throws {
        let diagnostics = try diagnosticsFor("""
        open class B { open fun f() = 0 }
        class A { class D { object O : B() { fun f() = 1 } } }
        """)
        assertHasDiagnostic("KSWIFTK-SEMA-OVERRIDE", in: diagnostics)
    }

    @Test
    func acceptsValidOverridesInNestedObject() throws {
        let diagnostics = try diagnosticsFor("""
        open class B {
            open var x: Any = 1
            open fun f(): Any = 1
        }
        class C {
            object O : B() {
                override var x: Any = 2
                override fun f(): String = "s"
            }
        }
        """)
        assertNoDiagnostic("KSWIFTK-SEMA-OVERRIDE", in: diagnostics)
        assertNoDiagnostic("KSWIFTK-SEMA-OVERRIDE-NOTHING", in: diagnostics)
        assertNoDiagnostic("KSWIFTK-SEMA-OVERRIDE-MUTABILITY", in: diagnostics)
        assertNoDiagnostic("KSWIFTK-SEMA-OVERRIDE-TYPE", in: diagnostics)
    }

    // MARK: - Companion objects

    @Test
    func rejectsMissingOverrideInCompanionObject() throws {
        let diagnostics = try diagnosticsFor("""
        open class B { open fun f() = 0 }
        class C { companion object : B() { fun f() = 1 } }
        """)
        assertHasDiagnostic("KSWIFTK-SEMA-OVERRIDE", in: diagnostics)
    }

    @Test
    func rejectsMissingOverrideInNamedCompanionObject() throws {
        let diagnostics = try diagnosticsFor("""
        open class B { open fun f() = 0 }
        class C { companion object Named : B() { fun f() = 1 } }
        """)
        assertHasDiagnostic("KSWIFTK-SEMA-OVERRIDE", in: diagnostics)
    }

    @Test
    func rejectsMissingOverrideInInterfaceCompanionObject() throws {
        let diagnostics = try diagnosticsFor("""
        open class B { open fun f() = 0 }
        interface I { companion object : B() { fun f() = 1 } }
        """)
        assertHasDiagnostic("KSWIFTK-SEMA-OVERRIDE", in: diagnostics)
    }

    @Test
    func rejectsValOverridingVarInCompanionObject() throws {
        let diagnostics = try diagnosticsFor("""
        open class B { open var x: Any = 1 }
        class C { companion object : B() { override val x: Any = 1 } }
        """)
        assertHasDiagnostic("KSWIFTK-SEMA-OVERRIDE-MUTABILITY", in: diagnostics)
    }

    @Test
    func acceptsValidOverridesInCompanionObject() throws {
        let diagnostics = try diagnosticsFor("""
        open class B {
            open var x: Any = 1
            open fun f(): Any = 1
        }
        class C {
            companion object : B() {
                override var x: Any = 2
                override fun f(): String = "s"
            }
        }
        """)
        assertNoDiagnostic("KSWIFTK-SEMA-OVERRIDE", in: diagnostics)
        assertNoDiagnostic("KSWIFTK-SEMA-OVERRIDE-NOTHING", in: diagnostics)
        assertNoDiagnostic("KSWIFTK-SEMA-OVERRIDE-MUTABILITY", in: diagnostics)
        assertNoDiagnostic("KSWIFTK-SEMA-OVERRIDE-TYPE", in: diagnostics)
    }

    // MARK: - Top-level objects

    @Test
    func rejectsMissingOverrideInTopLevelObject() throws {
        let diagnostics = try diagnosticsFor("""
        open class B { open fun f() = 0 }
        object Top : B() { fun f() = 1 }
        """)
        assertHasDiagnostic("KSWIFTK-SEMA-OVERRIDE", in: diagnostics)
    }

    @Test
    func rejectsMissingOverrideInTopLevelObjectImplementingInterface() throws {
        let diagnostics = try diagnosticsFor("""
        interface I { fun g(): Int }
        object Top : I { fun g() = 1 }
        """)
        // Abstract interface members surface as KSWIFTK-SEMA-ABSTRACT for
        // every owner kind; the member-level hiding check is covered by the
        // class-supertype cases above.
        assertHasDiagnostic("KSWIFTK-SEMA-ABSTRACT", in: diagnostics)
    }

    // MARK: - Enum entry bodies

    @Test
    func rejectsMissingOverrideInEnumEntryBody() throws {
        let diagnostics = try diagnosticsFor("""
        enum class E { A { fun h() = 1 }; open fun h() = 0 }
        """)
        assertHasDiagnostic("KSWIFTK-SEMA-OVERRIDE", in: diagnostics)
    }

    @Test
    func rejectsMissingOverrideInEnumEntryBodyHidingEnumMember() throws {
        let diagnostics = try diagnosticsFor("""
        interface I { fun g(): Int }
        enum class E : I {
            A { fun g() = 1 }
            ; override fun g() = 2
        }
        """)
        // The entry body's `fun g()` hides the enum's own `g` member.
        assertHasDiagnostic("KSWIFTK-SEMA-OVERRIDE", in: diagnostics)
    }

    @Test
    func rejectsMissingOverrideInSecondEnumEntryBody() throws {
        let diagnostics = try diagnosticsFor("""
        enum class E {
            A
            B { fun h() = 1 }
            ; open fun h() = 0
        }
        """)
        assertHasDiagnostic("KSWIFTK-SEMA-OVERRIDE", in: diagnostics)
    }

    @Test
    func rejectsValOverridingVarInEnumEntryBody() throws {
        let diagnostics = try diagnosticsFor("""
        enum class E {
            A { override val x: Any = 1 }
            ; open var x: Any = 2
        }
        """)
        assertHasDiagnostic("KSWIFTK-SEMA-OVERRIDE-MUTABILITY", in: diagnostics)
    }

    @Test
    func rejectsVarTypeMismatchInEnumEntryBody() throws {
        let diagnostics = try diagnosticsFor("""
        enum class E {
            A { override var x: String = "s" }
            ; open var x: Any = 1
        }
        """)
        assertHasDiagnostic("KSWIFTK-SEMA-OVERRIDE-TYPE", in: diagnostics)
    }

    @Test
    func acceptsValidOverridesInEnumEntryBody() throws {
        let diagnostics = try diagnosticsFor("""
        enum class E {
            A {
                override fun h() = 1
                override fun toString() = "a"
            }
            ; open fun h() = 0
        }
        """)
        assertNoDiagnostic("KSWIFTK-SEMA-OVERRIDE", in: diagnostics)
        assertNoDiagnostic("KSWIFTK-SEMA-OVERRIDE-NOTHING", in: diagnostics)
        assertNoDiagnostic("KSWIFTK-SEMA-OVERRIDE-MUTABILITY", in: diagnostics)
        assertNoDiagnostic("KSWIFTK-SEMA-OVERRIDE-TYPE", in: diagnostics)
    }
}
#endif
