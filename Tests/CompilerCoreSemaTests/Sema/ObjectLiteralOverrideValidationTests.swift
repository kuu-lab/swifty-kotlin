#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerTestSupport
import Foundation
import Testing

/// Anonymous object declarations (`object : A() { ... }`) are bound lazily
/// during type checking, so the open/final/override walk over
/// `topLevelDecls` never reached them and their members received no override
/// validation at all. kotlinc rejects every case below; kswiftc previously
/// accepted them all. Validation now runs as a deferred pass once member
/// symbols and types are published.
@Suite
struct ObjectLiteralOverrideValidationTests {
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
    func rejectsOverrideOfNonexistentMember() throws {
        let diagnostics = try diagnosticsFor("""
        open class A { open var x: Any = 1 }
        val o = object : A() { override var y: String = "s" }
        """)
        assertHasDiagnostic("KSWIFTK-SEMA-OVERRIDE-NOTHING", in: diagnostics)
    }

    @Test
    func rejectsOverrideOfNonexistentFunction() throws {
        let diagnostics = try diagnosticsFor("""
        open class A { open fun f() = 1 }
        val o = object : A() { override fun g() = 2 }
        """)
        assertHasDiagnostic("KSWIFTK-SEMA-OVERRIDE-NOTHING", in: diagnostics)
    }

    @Test
    func rejectsValOverridingVar() throws {
        let diagnostics = try diagnosticsFor("""
        open class A { open var x: Any = 1 }
        val o = object : A() { override val x: Any = 1 }
        """)
        assertHasDiagnostic("KSWIFTK-SEMA-OVERRIDE-MUTABILITY", in: diagnostics)
    }

    @Test
    func rejectsVarTypeMismatch() throws {
        let diagnostics = try diagnosticsFor("""
        open class A { open var x: Any = 1 }
        val o = object : A() { override var x: String = "s" }
        """)
        assertHasDiagnostic("KSWIFTK-SEMA-OVERRIDE-TYPE", in: diagnostics)
    }

    @Test
    func rejectsMemberHidingInheritedMember() throws {
        let diagnostics = try diagnosticsFor("""
        open class A { open var x: Any = 1 }
        val o = object : A() { var x: Any = 1 }
        """)
        assertHasDiagnostic("KSWIFTK-SEMA-OVERRIDE", in: diagnostics)
    }

    @Test
    func acceptsValidOverrides() throws {
        let diagnostics = try diagnosticsFor("""
        open class A {
            open var x: Any = 1
            open fun f(): Any = 1
        }
        val o = object : A() {
            override var x: Any = 2
            override fun f(): String = "s"
        }
        """)
        assertNoDiagnostic("KSWIFTK-SEMA-OVERRIDE-NOTHING", in: diagnostics)
        assertNoDiagnostic("KSWIFTK-SEMA-OVERRIDE-MUTABILITY", in: diagnostics)
        assertNoDiagnostic("KSWIFTK-SEMA-OVERRIDE-TYPE", in: diagnostics)
    }

    @Test
    func rejectsOverrideInsideNestedObjectLiteral() throws {
        let diagnostics = try diagnosticsFor("""
        open class A { open var x: Any = 1 }
        val outer = object {
            val inner = object : A() { override var y: String = "s" }
        }
        """)
        assertHasDiagnostic("KSWIFTK-SEMA-OVERRIDE-NOTHING", in: diagnostics)
    }

    @Test
    func rejectsOverrideInsideLocalObjectLiteral() throws {
        let diagnostics = try diagnosticsFor("""
        open class A { open var x: Any = 1 }
        fun make() = object : A() { override var y: String = "s" }
        """)
        assertHasDiagnostic("KSWIFTK-SEMA-OVERRIDE-NOTHING", in: diagnostics)
    }

    // Local classes declared inside function bodies bind through
    // `.localNominalDecl` expressions, which the OFO walk also missed.

    @Test
    func rejectsOverrideOfNonexistentMemberInLocalClass() throws {
        let diagnostics = try diagnosticsFor("""
        open class A { open var x: Any = 1 }
        fun f() { class L : A() { override var y: String = "s" } }
        """)
        assertHasDiagnostic("KSWIFTK-SEMA-OVERRIDE-NOTHING", in: diagnostics)
    }

    @Test
    func rejectsVarTypeMismatchInLocalClass() throws {
        let diagnostics = try diagnosticsFor("""
        open class A { open var x: Any = 1 }
        fun f() { class L : A() { override var x: String = "s" } }
        """)
        assertHasDiagnostic("KSWIFTK-SEMA-OVERRIDE-TYPE", in: diagnostics)
    }

    @Test
    func rejectsValOverridingVarInLocalClass() throws {
        let diagnostics = try diagnosticsFor("""
        open class A { open var x: Any = 1 }
        fun f() { class L : A() { override val x: Any = 1 } }
        """)
        assertHasDiagnostic("KSWIFTK-SEMA-OVERRIDE-MUTABILITY", in: diagnostics)
    }

    @Test
    func rejectsMemberHidingInheritedMemberInLocalClass() throws {
        let diagnostics = try diagnosticsFor("""
        open class A { open var x: Any = 1 }
        fun f() { class L : A() { var x: Any = 1 } }
        """)
        assertHasDiagnostic("KSWIFTK-SEMA-OVERRIDE", in: diagnostics)
    }

    @Test
    func acceptsValidOverridesInLocalClass() throws {
        let diagnostics = try diagnosticsFor("""
        open class A {
            open var x: Any = 1
            open fun f(): Any = 1
        }
        fun f() {
            class L : A() {
                override var x: Any = 2
                override fun f(): String = "s"
            }
        }
        """)
        assertNoDiagnostic("KSWIFTK-SEMA-OVERRIDE-NOTHING", in: diagnostics)
        assertNoDiagnostic("KSWIFTK-SEMA-OVERRIDE-MUTABILITY", in: diagnostics)
        assertNoDiagnostic("KSWIFTK-SEMA-OVERRIDE-TYPE", in: diagnostics)
    }

    @Test
    func rejectsOverrideInLocalClassNestedInLocalClass() throws {
        let diagnostics = try diagnosticsFor("""
        open class A { open var x: Any = 1 }
        fun f() {
            class Outer {
                class Inner : A() { override var y: String = "s" }
            }
        }
        """)
        assertHasDiagnostic("KSWIFTK-SEMA-OVERRIDE-NOTHING", in: diagnostics)
    }

    // KUU-4300: the object literal's `declBySymbolCache` reverse map was built
    // with `Dictionary(uniqueKeysWithValues:)`, which trapped whenever
    // `bindings.declSymbols` bound two decls to one symbol deduplicated by
    // `SymbolTable.define` (e.g. a repeated `class Dup`). An `override` member
    // without an explicit visibility modifier forces the cache build during
    // implicit-visibility resolution, so the whole sema pass crashed instead
    // of reporting the redeclaration.
    @Test
    func reportsRedeclarationInsteadOfTrappingOnDedupSymbol() throws {
        let diagnostics = try diagnosticsFor("""
        interface I { fun f() }
        class Dup {}
        class Dup {}
        fun make() {
            val o = object : I { override fun f() {} }
        }
        """)
        assertHasDiagnostic("KSWIFTK-SEMA-0001", in: diagnostics)
    }

    // Same dedup-symbol trap on the property path: an `override var` with no
    // explicit visibility forces both the implicit setter visibility and the
    // implicit member visibility lookups, each of which builds the reverse
    // declBySymbol map.
    @Test
    func reportsRedeclarationInsteadOfTrappingOnDedupSymbolForProperty() throws {
        let diagnostics = try diagnosticsFor("""
        interface I { var x: Int }
        class Dup {}
        class Dup {}
        fun make() {
            val o = object : I { override var x: Int = 1 }
        }
        """)
        assertHasDiagnostic("KSWIFTK-SEMA-0001", in: diagnostics)
    }

    // KUU-4336: the same trap triggered by same-kind *property* redeclarations
    // (`val Symbol` twice binds two decls to one symbol) with the anonymous
    // object literal in a top-level property initializer instead of a function
    // body. kswiftc --emit library used to trap with
    // `Duplicate values for key: 'SymbolID(...)'` instead of reporting
    // SEMA-0001.
    @Test
    func reportsRedeclarationInsteadOfTrappingOnDedupPropertySymbol() throws {
        let diagnostics = try diagnosticsFor("""
        val Symbol = 1
        val Symbol = 2
        interface I { fun f() }
        val o = object : I { override fun f() {} }
        """)
        assertHasDiagnostic("KSWIFTK-SEMA-0001", in: diagnostics)
    }
}
#endif
