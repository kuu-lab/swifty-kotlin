@testable import CompilerCore
import Foundation
import Testing

/// Regression coverage for a supertype-resolution gap: `bindInheritanceEdges`
/// (Sources/CompilerCore/Sema/DataFlow/Inheritance.swift) resolved an
/// unqualified supertype name against the file's own `imports` list using
/// logic that only matched an *explicit* import (`import pkg.Name` or
/// `import pkg.Name as Alias`) by its last path component. A wildcard import
/// (`import pkg.*`) carries no such name component, so a supertype visible
/// only through a wildcard import silently dropped out of `directSupertypes`
/// -- the implementing class ended up with only `kotlin.Any` recorded, even
/// though ordinary expression-level member-call resolution (built via
/// `ScopeBuilder`, a separate code path) saw the wildcard-imported type fine.
/// This produced several symptoms depending on where the missing supertype
/// edge was consulted: unresolved member-function calls through the
/// interface, "no viable overload" at expected-type constructor call sites,
/// and (unverified here) runtime failures for `as`-casts relying on the
/// vtable/itable built from `directSupertypes`.
@Suite
struct WildcardImportSupertypeResolutionTests {
    private let probeSource = """
    package probe

    interface Foo
    """

    @Test
    func testWildcardImportedInterfaceRecordedAsDirectSupertype() throws {
        let mainSource = """
        import probe.*

        class F : Foo
        """

        let ctx = makeContextFromSources([probeSource, mainSource])
        try runSema(ctx)

        let sema = try #require(ctx.sema)
        let interner = ctx.interner

        let fooSym = try #require(sema.symbols.lookup(fqName: [
            interner.intern("probe"),
            interner.intern("Foo"),
        ]))
        let fSym = try #require(sema.symbols.lookup(fqName: [interner.intern("F")]))

        let directSupertypes = sema.symbols.directSupertypes(for: fSym)
        #expect(
            directSupertypes.contains(fooSym),
            "F should list probe.Foo as a direct supertype via the wildcard import, got: \(directSupertypes)"
        )
    }

    @Test
    func testWildcardImportedInterfaceExpectedTypeAssignmentResolves() throws {
        let mainSource = """
        import probe.*

        fun act(f: Foo): String = "handled"

        class F : Foo

        fun useIt(): String {
            val f: Foo = F()
            return act(f)
        }
        """

        let ctx = makeContextFromSources([probeSource, mainSource])
        try runSema(ctx)

        #expect(
            ctx.diagnostics.diagnostics.isEmpty,
            "Expected F() to satisfy the Foo-typed val/parameter via the wildcard import, got: \(ctx.diagnostics.diagnostics)"
        )
    }

    /// The literal task repro: a same-named extension function declared on the
    /// wildcard-imported interface, called on an implementing class instance.
    /// This is the call shape that motivated the original (incorrect) "adjacent
    /// same-name extension functions" hypothesis -- the real defect had nothing
    /// to do with extensions or having two of them; it reproduces with exactly
    /// one, because `F`'s recorded supertypes never included `Foo` at all.
    @Test
    func testWildcardImportedInterfaceExtensionFunctionCallResolves() throws {
        let mainSource = """
        import probe.*

        fun Foo.act(): String = "handled"

        class F : Foo

        fun useIt(): String = F().act()
        """

        let ctx = makeContextFromSources([probeSource, mainSource])
        try runSema(ctx)

        #expect(
            ctx.diagnostics.diagnostics.isEmpty,
            "Expected F().act() to resolve the Foo extension through the wildcard import, got: \(ctx.diagnostics.diagnostics)"
        )
    }

    @Test
    func testWildcardImportedInterfaceAsTypeArgumentResolves() throws {
        let mainSource = """
        import probe.*

        class Box : Comparable<Foo> {
            override fun compareTo(other: Foo): Int = 0
        }
        """

        let ctx = makeContextFromSources([probeSource, mainSource])
        try runSema(ctx)

        let sema = try #require(ctx.sema)
        let interner = ctx.interner

        let comparableSym = try #require(sema.symbols.lookup(fqName: [
            interner.intern("kotlin"),
            interner.intern("Comparable"),
        ]))
        let boxSym = try #require(sema.symbols.lookup(fqName: [interner.intern("Box")]))

        #expect(
            sema.symbols.directSupertypes(for: boxSym).contains(comparableSym),
            "Box should list kotlin.Comparable as a direct supertype"
        )
        let typeArgs = sema.symbols.supertypeTypeArgs(for: boxSym, supertype: comparableSym)
        #expect(
            !typeArgs.isEmpty,
            "Comparable<Foo>'s type argument should resolve through the wildcard import instead of being dropped"
        )
        #expect(
            ctx.diagnostics.diagnostics.isEmpty,
            "Expected compareTo(other: Foo) to be recognized as an override of Comparable<Foo>.compareTo, got: \(ctx.diagnostics.diagnostics)"
        )
    }

    @Test
    func testExplicitImportTakesPrecedenceOverWildcardImportForSameName() throws {
        let otherProbeSource = """
        package otherprobe

        interface Foo
        """
        let mainSource = """
        import probe.*
        import otherprobe.Foo

        class F : Foo
        """

        let ctx = makeContextFromSources([probeSource, otherProbeSource, mainSource])
        try runSema(ctx)

        let sema = try #require(ctx.sema)
        let interner = ctx.interner

        let otherFooSym = try #require(sema.symbols.lookup(fqName: [
            interner.intern("otherprobe"),
            interner.intern("Foo"),
        ]))
        let probeFooSym = try #require(sema.symbols.lookup(fqName: [
            interner.intern("probe"),
            interner.intern("Foo"),
        ]))
        let fSym = try #require(sema.symbols.lookup(fqName: [interner.intern("F")]))

        let directSupertypes = sema.symbols.directSupertypes(for: fSym)
        #expect(
            directSupertypes.contains(otherFooSym),
            "F should resolve Foo against the explicit import (otherprobe.Foo), got: \(directSupertypes)"
        )
        #expect(
            !directSupertypes.contains(probeFooSym),
            "F should not also pick up probe.Foo from the wildcard import once the explicit import matches, got: \(directSupertypes)"
        )
    }
}
